## SUMMARY ##

# Embeds the rendered analysis report (www/analysis.html, copied there by
# R/build.R). The iframe is only created once the tab is first opened, so the
# ~17 MB report isn't downloaded by visitors who never view it.

summaryUI <- function() {
  uiOutput("summary_frame", fill = TRUE)
}

summaryServer <- function(input, output) {
  opened <- reactiveVal(FALSE)

  observe({
    if (identical(input$nav, "Summary")) opened(TRUE)
  })

  output$summary_frame <- renderUI({
    req(opened())
    if (!file.exists("www/analysis.html")) {
      return(div(
        class = "page-content",
        p(
          "The data summary report hasn't been built yet. Run R/build.R to render it."
        )
      ))
    }
    tags$iframe(
      src = "analysis.html",
      title = "Data summary report",
      class = "summary-frame"
    )
  })
}
