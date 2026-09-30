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
  "Not detected" = "#b9b8b1"
)

no_data_color <- "#e2e5e9"


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
    transmute(site_type, top_analyte = as.character(analyte), top_freq = det_freq)

  exc <- app_status |>
    filter(analyte == "Total", benchmark == "primary") |>
    summarize(pct_exceed = mean(status == "Exceeds"), .by = site_type)

  det |>
    left_join(top, join_by(site_type)) |>
    left_join(exc, join_by(site_type))
})


# UI helpers -------------------------------------------------------------------

build_link <- function(text, href, ...) {
  a(text, href = href, target = "_blank", .noWS = "outside", ...)
}

# shown at the bottom of the About page (a page_navbar footer overlaps
# non-fillable pages)
site_footer <- function() {
  tags$footer(
    class = "site-footer",
    div(
      "Data: Wisconsin Department of Agriculture, Trade and Consumer Protection (DATCP).",
      sprintf("Samples through %s · Updated %s.", format(last_sample_date, "%B %Y"), last_updated)
    ),
    div("Developed with UW–Madison Extension, Clean Wisconsin, and the River Alliance of Wisconsin.")
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
