## SUMMARY ##

# Embeds the rendered analysis report (www/analysis.html, copied there by
# R/build.R). The iframe is only created once the tab is first opened, so the
# ~17 MB report isn't downloaded by visitors who never view it.

summaryUI <- function() {
  report_date <- if (file.exists("www/analysis.html")) {
    format(file.mtime("www/analysis.html"), "%B %Y")
  }

  div(
    class = "summary-page",
    div(
      class = "summary-header",
      div(
        class = "summary-title",
        h1("Data summary"),
        div(
          tags$a(
            href = "analysis.html",
            download = "neonicotinoids-wisconsin-summary.html",
            class = "btn btn-outline-primary btn-sm",
            bs_icon("download"),
            "Download report (HTML)"
          ),
          tags$a(
            href = "analysis.html",
            target = "_blank",
            class = "btn btn-outline-primary btn-sm",
            bs_icon("box-arrow-up-right"),
            "Open in new tab"
          )
        )
      ),
      p(
        "A prepared report on the full DATCP monitoring dataset: sampling effort, detection frequency and trends, concentrations, and benchmark exceedances for surface water and groundwater.",
        if (!is.null(report_date)) paste0("Updated ", report_date, ".")
      )
    ),
    div(
      class = "summary-body",
      uiOutput("summary_frame", fill = TRUE)
    ) |>
      as_fill_carrier()
  ) |>
    as_fill_carrier()
}

summaryServer <- function(input, output) {
  opened <- reactiveVal(FALSE)

  observe({
    if (identical(input$nav, "Summary")) opened(TRUE)
  })

  output$summary_frame <- renderUI({
    req(opened())
    if (!file.exists("www/analysis.html")) {
      return(p(
        "The data summary report hasn't been built yet. Run R/build.R to render it."
      ))
    }
    # the page header above replaces the report's own title block (hidden
    # here rather than in analysis.css so the download keeps it)
    tags$iframe(
      src = "analysis.html",
      title = "Data summary report",
      class = "summary-frame"
      # onload = "try { var s = this.contentDocument.createElement('style'); s.textContent = '#title-block-header { display: none; }'; this.contentDocument.head.appendChild(s); } catch (e) {}"
    ) |>
      as_fill_item()
  })
}
