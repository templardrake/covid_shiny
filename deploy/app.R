library(shiny)
library(shinyWidgets)
library(plotly)
library(shinydashboard)

# get population density-normalized cumulative COVID deaths data
source("data.R")
df_orig <- getData()

# function to turn a string term into a formula
tilde <- function(term) as.formula(paste0("~`", term, "`"))

# function to add a trace to a Plotly plot
add_country <- function(country, plot)
  plot %>% add_trace(y = tilde(country), name = country, mode = 'lines')

ui <- dashboardPage(title = "COVID Data Explorer", skin = "black",

  header = dashboardHeader(
    title = "COVID Data Explorer",
    titleWidth = "250px"
  ),

  sidebar = dashboardSidebar(
    width = "250px",
    pickerInput("user_countries", "Select countries",
      choices = rownames(df_orig),
      options = list(`actions-box` = TRUE),
      multiple = T,
      selected = c("Ireland", "US", "Italy", "United Kingdom", "Spain", "France", "Germany", "Japan"),
      width = "100%"
    ),
    selectInput("alignx", "Align x-axis on...",
      choices = c("Date", "Days Since..."),
      selected = "Date"
    ),
    uiOutput("days_since"),
    checkboxInput("logy", "Logarithmic y-axis?")
  ),

  body = dashboardBody(
    fluidRow(
      column(width = 12,
        box(width = "100%",
          plotlyOutput("plot", width = "100%")
        )
      )
    )
  )
)

server <- function(input, output) {
  
  # listen to x-axis alignment selection and render this separately from other UI
  observe({
    if (input$alignx == "Days Since...")
      output$days_since <- renderUI(
        sliderInput("xaxis_rate_align", "...cumulative normalized deaths", 0.1, 100, 0.1, 0.1))
    else
      output$days_since <- NULL
  })
  
  observe({  
    
    # create plot only if user has selected at least one country
    len <- length(input$user_countries)
    if (len > 0) {
      
      # copy original data, but only use user-selected countries
      df <- df_orig[input$user_countries, ]
      countries <- NULL
      
      # transposed data with additional "Date" column
      if (input$alignx == "Date") {
        
        # what to plot along the x-axis
        xval <- "Date"
        
        # transpose and add a Date column
        tf <- as.data.frame(t(df))
        tf$Date <- as.Date(rownames(tf))
        
        # countries to use? all of them
        countries <- input$user_countries
        
      # complex row-wise shifting of data
      } else if (input$alignx == "Days Since...") {
        
        # what to plot along the x-axis
        xval <- "Days Since..."
        minrate <- if (is.null(input$xaxis_rate_align)) 0.1 else input$xaxis_rate_align
        
        # get day (index) where country first met or exceeded `minrate` density-normalized cumulative deaths
        start <- as.vector(tail(apply(df < minrate, 1, cumsum), n = 1)) + 1
        
        # if number of days > `start`, country hasn't had that many cases yet
        n_days <- ncol(df)
        
        # these are all the countries with >= `minrate` cumulative deaths rate
        countries <- rownames(df)[start < n_days]
        
        if (length(countries) > 0) {
        
          # rewrite data frame and start date list
          df <- df[countries, ]
          start <- start[start < n_days]
          names(start) <- countries
          
          # shift all rows to the left by `start` columns
          minoffset <- min(start)
          offset <- start-minoffset
          
          # This is the most complicated part -- we need to "shift" each row of the data frame.
          # If Japan has an offset of -49, we need to move every element of the "Japan" row
          # 49 columns to the right. If Luxembourg has an offset of 5, we need to move every
          # element of the "Luxembourg" row 5 columns to the left.
          
          shift <- function(df, row, by) {
            nr <- nrow(df)
            if (by == 0 || row > nr || row < 1) df
            else {
              nc <- ncol(df)
              if (abs(by) >= nc) {
                df[row, ] <- rep(NA, nc)
                df
              } else if (by > 0) {
                df[row, 1:(nc-by)] <- df[row, (1+by):nc]
                df[row, (nc-by+1):nc] <- NA
                df
              } else {
                df[row, (1-by):nc] <- df[row, 1:(nc+by)]
                df[row, 1:(-by)] <- NA
                df
              }
            }
          }
          
          # shift all rows by the appropriate amount
          for (ii in 1:length(countries)) df <- shift(df, ii, offset[ii])
          
          # finally, transpose and add "Days Since..." column, similar to above
          tf <- as.data.frame(t(df))
          tf$`Days Since...` <- (-minoffset+1):(nrow(tf)-minoffset)
        }
      }
        
      # create plot only if at least one country is left after any filtering
      len <- length(countries)
      if (len > 0) {
      
        # create plot with first country
        first_country <- countries[1]
        plot <- plot_ly(tf, x=tilde(xval), y=tilde(first_country), name=first_country, type="scatter", mode="lines")
    
        # add all additional countries in a loop
        if (len >1) for (ii in 2:len) plot <- add_country(countries[ii], plot)
        
        # handle linear / logarithmic y-axis
        yaxis <- list(title=HTML("Cumulative Deaths / Capita / km<sup>2</sup>"), tickprefix="   ")
        if (input$logy) yaxis <- c(yaxis, type="log")
    
        plot <- plot %>% layout(
          title = HTML("Cumulative Deaths / Capita / km<sup>2</sup>"),
          xaxis = list(title = xval),
          yaxis = yaxis,
          margin = list(l = 50, r = 50, b = 80, t = 80, pad = 20)
        )
        
        output$plot <- renderPlotly(plot)
      }
    }
  })
}

shinyApp(ui = ui, server = server)