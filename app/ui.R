##  MAIN UI  ##

ui <- page_navbar(
  id = "nav",
  title = span(
    class = "navbar-title",
    "Neonicotinoids in Wisconsin Waters"
  ),
  window_title = "Neonicotinoids in Wisconsin Waters",
  lang = "en",
  fillable = "Explore",
  navbar_options = navbar_options(
    bg = brand$red,
    theme = "dark",
    underline = TRUE
  ),

  theme = bs_theme(
    version = 5,
    primary = brand$red,
    fg = brand$text,
    bg = "#ffffff",
    base_font = font_google("Red Hat Text", wght = c(400, 500), local = FALSE),
    heading_font = font_google(
      "Red Hat Display",
      wght = c(500, 700),
      local = FALSE
    ),
    "navbar-brand-font-size" = "1.15rem"
  ),

  header = tags$head(
    tags$meta(
      name = "description",
      content = "Neonicotinoid insecticide monitoring results for Wisconsin surface water and groundwater, from DATCP monitoring data."
    ),
    tags$link(rel = "icon", type = "image/svg+xml", href = "favicon.svg"),
    tags$link(rel = "icon", type = "image/png", sizes = "32x32", href = "favicon-32.png"),
    tags$link(rel = "icon", type = "image/png", sizes = "16x16", href = "favicon-16.png"),
    tags$link(rel = "apple-touch-icon", sizes = "180x180", href = "apple-touch-icon.png"),
    tags$meta(name = "theme-color", content = brand$red),
    tags$link(rel = "stylesheet", type = "text/css", href = "styles.css"),
    reduced_motion_js
  ),

  # Pages ----
  nav_panel("About", aboutUI(), icon = bs_icon("info-circle")),
  nav_panel("Summary", summaryUI(), icon = bs_icon("file-text"), class = "p-0"),
  nav_panel("Explore", exploreUI(), icon = bs_icon("map"))

  # partner links are in the About page footer: a menu inside the navbar's
  # tab list is invalid ARIA (aria-required-children, listitem)
)
