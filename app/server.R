##  MAIN SERVER  ##

server <- function(input, output, session) {
  # shared links: open the requested page (or Explore for map parameters),
  # then strip the parameters so the address bar shows the clean app URL
  observeEvent(TRUE, once = TRUE, {
    q <- parseQueryString(session$clientData$url_search)
    if (!is.null(q$page) && q$page %in% c("About", "Summary", "Explore")) {
      nav_select("nav", q$page)
    } else if (length(q) > 0) {
      nav_select("nav", "Explore")
    }
    if (length(q) > 0) session$sendCustomMessage("clear-url", TRUE)
  })

  observeEvent(input$go_explore, nav_select("nav", "Explore"))
  observeEvent(input$go_summary, nav_select("nav", "Summary"))

  summaryServer(input, output)
  explore_query <- exploreServer()

  # Share ----

  observeEvent(input$share, {
    query <- if (input$nav == "Explore") {
      explore_query()
    } else {
      paste0("page=", URLencode(input$nav, reserved = TRUE))
    }
    showModal(modalDialog(
      title = "Share this view",
      p("Copy this link to share the current page and map selections."),
      tags$input(
        id = "share_url",
        type = "text",
        class = "form-control",
        readonly = NA,
        `aria-label` = "Link to this view"
      ),
      footer = tagList(
        tags$button(
          id = "share_copy",
          type = "button",
          class = "btn btn-primary",
          bs_icon("clipboard"),
          span("Copy link")
        ),
        modalButton("Close")
      ),
      easyClose = TRUE
    ))
    session$sendCustomMessage("share-url", query)
  })
}
