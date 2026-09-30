##  MAIN SERVER  ##

server <- function(input, output, session) {
  # open the Explore page directly for shared links with map parameters
  observeEvent(TRUE, once = TRUE, {
    q <- parseQueryString(session$clientData$url_search)
    if (length(q) > 0) nav_select("nav", "Explore")
  })

  observeEvent(input$go_explore, nav_select("nav", "Explore"))
  observeEvent(input$go_summary, nav_select("nav", "Summary"))

  summaryServer(input, output)
  exploreServer()
}
