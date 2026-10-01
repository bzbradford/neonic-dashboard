##  GLOBAL  ##

# Load packages ----------------------------------------------------------------

library(sf)

suppressPackageStartupMessages({
  library(tidyverse)
  library(shiny)
  library(bslib)
  library(bsicons)
  library(htmltools)
  library(mapgl)
  library(plotly)
  library(reactable)
})


# Development ------------------------------------------------------------------

if (FALSE) {
  # rebuild data, analysis report, and copy the report into www/
  # (run from the project root)
  source("R/build.R")

  # renv for project root
  renv::update()
  renv::snapshot()

  # build renv lockfile for the app subdirectory (run from the project root)
  renv::snapshot(
    project = "app",
    library = renv::paths$library(), # the root project's library
    lockfile = "app/renv.lock",
    prompt = FALSE
  )

  # run the app
  shiny::devmode(TRUE)
  shiny::runApp("app")
}


# Data -------------------------------------------------------------------------

load("data.RData") # created by R/prep_data.R
source("functions.R")

# data provenance for the footer
last_sample_date <- max(results$date)
last_updated <- format(file.info("data.RData")$mtime, "%Y-%m-%d")


# Definitions ------------------------------------------------------------------

## choices ----

water_choices <- c(
  "Surface water" = "Surface water",
  "Groundwater" = "Groundwater",
  "Both" = "Both"
)

analyte_choices <- c(
  "Imidacloprid" = "Imidacloprid",
  "Clothianidin" = "Clothianidin",
  "Thiamethoxam" = "Thiamethoxam",
  "Any neonicotinoid" = "Total"
)

geo_choices <- c(
  "Counties" = "county",
  "DNR watersheds" = "wshed",
  "Sites only" = "sites"
)

metric_choices <- c(
  "Detection frequency" = "det_freq",
  "Sites with detections" = "pct_sites_det",
  "Median detected concentration" = "median_det",
  "Samples exceeding benchmark" = "pct_exceed"
)

benchmark_choices <- c(
  "Primary (depends on water type)" = "primary",
  "EPA aquatic acute" = "aquatic_acute",
  "EPA aquatic chronic" = "aquatic_chronic",
  "Proposed WI enforcement standard (ES)" = "proposed_es",
  "Proposed WI preventive action limit (PAL)" = "proposed_pal"
)

well_choices <- c(
  "All wells" = "all",
  "Private wells" = "private",
  "Monitoring wells & piezometers" = "monitoring"
)

year_range <- range(results$year)

## map colors ----

site_status_colors <- c(
  "Exceeded benchmark" = status_colors[["Exceeds"]],
  "Detected" = "#2a78d6",
  "Not detected" = "#8f8e88" # 3.1:1 against the basemap (WCAG non-text)
)

no_data_color <- "#e2e5e9"

# selected place outline: amber core on a dark casing, distinct from both the
# blue (frequency) and red (concentration, exceedance) ramps
sel_colors <- list(core = "#ffc20a", casing = brand$text)


# Precomputed tables -----------------------------------------------------------

site_geo_cols <- c("county", "wshed_code", "well_use", "private_well")

## app_results ----
# featured analytes + total, with site geography (one row per sample x analyte)
app_results <- featured_results(results, samples) |>
  add_site_geo(sites, site_geo_cols) |>
  mutate(site_key = paste(site_type, site_id, sep = "|"))

## app_status ----
# benchmark status per sample x analyte x benchmark
app_status <- build_sample_status(exceedances, benchmarks) |>
  add_site_geo(sites, site_geo_cols)

## app_sites ----
app_sites <- sites |>
  mutate(site_key = paste(site_type, site_id, sep = "|")) |>
  left_join(
    build_site_popups(sites, site_analytes),
    join_by(site_type, site_id)
  ) |>
  st_as_sf(coords = c("map_lon", "map_lat"), crs = 4326, remove = FALSE)

## geography lookups ----
county_names <- counties |>
  st_drop_geometry() |>
  transmute(key = county, name = paste(county, "County"))

wshed_names <- watersheds |>
  st_drop_geometry() |>
  transmute(key = wshed_code, name = paste(wshed_name, "watershed"))

geo_layers <- list(
  county = list(
    col = "county",
    shapes = counties |> transmute(key = county),
    names = county_names
  ),
  wshed = list(
    col = "wshed_code",
    shapes = watersheds |> transmute(key = wshed_code),
    names = wshed_names
  )
)

wi_bbox <- st_bbox(wi_state)

## find_choices ----
# searchable list of every selectable place; values are "type:key"
find_choices <- local({
  opts <- function(type, keys, names) {
    set_names(paste0(type, ":", keys), names)
  }
  site_opts <- function(type) {
    s <- filter(app_sites, site_type == type) |> arrange(site_label)
    opts("site", s$site_key, s$site_label)
  }
  list(
    "Counties" = opts("county", county_names$key, county_names$name),
    "DNR watersheds" = opts("wshed", wshed_names$key, wshed_names$name),
    "Surface water sites" = site_opts("Surface water"),
    "Groundwater sites" = site_opts("Groundwater")
  )
})

## headline stats (About page) ----

headline_stats <- local({
  det <- samples |>
    summarize(
      n_samples = n(),
      n_sites = n_distinct(site_id),
      years = paste0(min(year), "–", max(year)),
      pct_detected = mean(any_detected),
      .by = site_type
    )

  top <- app_results |>
    filter(analyte != "Total") |>
    summarize_detections(site_type, analyte) |>
    slice_max(det_freq, n = 1, by = site_type) |>
    transmute(
      site_type,
      top_analyte = as.character(analyte),
      top_freq = det_freq
    )

  exc <- app_status |>
    filter(analyte == "Total", benchmark == "primary") |>
    summarize(pct_exceed = mean(status == "Exceeds"), .by = site_type)

  det |>
    left_join(top, join_by(site_type)) |>
    left_join(exc, join_by(site_type))
})


# UI helpers -------------------------------------------------------------------

# external link that opens in a new tab, announced to screen readers
build_link <- function(text, href, ...) {
  a(
    text,
    span(class = "visually-hidden", " (opens in a new tab)", .noWS = "outside"),
    href = href,
    target = "_blank",
    rel = "noopener",
    .noWS = "outside",
    ...
  )
}

# shown at the bottom of the About page (a page_navbar footer overlaps
# non-fillable pages)
site_footer <- function() {
  tags$footer(
    class = "site-footer",
    div(
      "Data: Wisconsin Department of Agriculture, Trade and Consumer Protection (DATCP).",
      sprintf(
        "Samples through %s · Updated %s.",
        format(last_sample_date, "%B %Y"),
        last_updated
      )
    ),
    div(
      "Developed with ",
      build_link("UW–Madison Extension", "https://extension.wisc.edu/"),
      ", ",
      build_link("Clean Wisconsin", "https://www.cleanwisconsin.org/"),
      ", and the ",
      build_link("River Alliance of Wisconsin", "https://wisconsinrivers.org/"),
      ". Data from ",
      build_link("Wisconsin DATCP", "https://datcp.wi.gov/"),
      "."
    )
  )
}

echo <- function(x) {
  message(deparse(substitute(x)))
  print(x)
}


# Source files -----------------------------------------------------------------

for (file in list.files("src", pattern = "\\.[Rr]$", full.names = TRUE)) {
  source(file)
}
