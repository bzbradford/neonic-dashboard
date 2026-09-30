## SHARED FUNCTIONS ##

# Analysis helpers used by both analysis.qmd and the Shiny app, so both compute
# every number the same way. Expects the tidyverse to be loaded and the objects
# in data.RData (built by R/prep_data.R) to be available.

# Colors -----------------------------------------------------------------------

brand <- list(
  red = "#c5050c",
  red_dark = "#9b0000",
  page_bg = "#f5f7fa",
  text = "#1f2328",
  muted = "#898781",
  grid = "#e1e0d9",
  no_data = "#e2e5e9"
)

# fixed categorical order (first three slots validate all-pairs for CVD)
analyte_colors <- c(
  Imidacloprid = "#2a78d6",
  Clothianidin = "#eb6834",
  Thiamethoxam = "#1baf7a",
  Total = "#52514e"
)

status_colors <- c(
  Exceeds = "#d03b3b",
  Below = "#86b6ef",
  Indeterminate = "#d9d8d2"
)

# sequential ramps: concentration = reds (brand), detection frequency = blues
conc_ramp <- c("#fde0dd", "#f4a3a0", "#e0504f", "#c5050c", "#7a0006")
freq_ramp <- c("#cde2fb", "#86b6ef", "#3987e5", "#1c5cab", "#0d366b")


# Formatting -------------------------------------------------------------------

fmt_n <- function(x) scales::comma(x, accuracy = 1)

fmt_pct <- function(x, digits = 1) {
  scales::percent(x, accuracy = 10^-digits)
}

# concentrations to 3 significant figures
fmt_conc <- function(x, units = TRUE) {
  out <- vapply(
    x,
    \(v) {
      if (is.na(v)) {
        return(NA_character_)
      }
      format(
        signif(v, 3),
        big.mark = ",",
        scientific = FALSE,
        drop0trailing = TRUE
      )
    },
    character(1)
  )
  if (units) if_else(is.na(out), NA_character_, paste(out, "µg/L")) else out
}

fmt_date_range <- function(from, to) {
  if_else(
    year(from) == year(to),
    as.character(year(from)),
    paste0(year(from), "–", year(to))
  )
}


# Data helpers -----------------------------------------------------------------

## add_total_analyte ----
# D4: append the combined total as a pseudo-analyte "Total", one row per sample
# event: detected if any analyte was, result = sum of detected concentrations
add_total_analyte <- function(results, samples) {
  total <- samples |>
    transmute(
      site_type,
      site_id,
      date,
      year,
      month,
      sample_seq,
      analyte = "Total",
      featured = TRUE,
      detected = any_detected,
      estimated = FALSE,
      result = total_conc,
      dl = NA_real_
    )

  bind_rows(mutate(results, analyte = as.character(analyte)), total) |>
    mutate(analyte = factor(analyte, c(levels(results$analyte), "Total")))
}

## featured_results ----
# the three featured analytes plus the total, as used in the app
featured_results <- function(results, samples) {
  add_total_analyte(results, samples) |>
    filter(featured) |>
    mutate(analyte = factor(analyte, names(analyte_colors)))
}

## apply_reporting_level ----
# D10: re-censor results at a common reporting level so detection frequency is
# comparable across years with different detection limits. Samples whose
# detection limit is above the level are dropped (can't be classified).
apply_reporting_level <- function(results, level) {
  results |>
    filter(dl <= level) |>
    mutate(
      detected = detected & result >= level,
      result = if_else(detected, result, NA_real_)
    )
}

## add_site_geo ----
# attach county / watershed / well metadata from the sites table
add_site_geo <- function(
  df,
  sites,
  cols = c("county", "wshed_code", "wshed_name", "well_use", "private_well")
) {
  left_join(
    df,
    select(sites, site_type, site_id, all_of(cols)),
    join_by(site_type, site_id)
  )
}


# Summaries --------------------------------------------------------------------

## summarize_detections ----
# D5: detection frequency is the headline metric; concentration stats are
# computed over detections only
summarize_detections <- function(results, ...) {
  results |>
    summarize(
      n_sites = n_distinct(site_id),
      n_samples = n(),
      n_detected = sum(detected),
      det_freq = n_detected / n_samples,
      n_sites_detected = n_distinct(site_id[detected]),
      median_det = median(result, na.rm = TRUE),
      mean_det = mean(result, na.rm = TRUE),
      max_det = suppressWarnings(max(result, na.rm = TRUE)),
      first_date = min(date),
      last_date = max(date),
      .by = c(...)
    ) |>
    mutate(across(
      c(median_det, mean_det, max_det),
      ~ if_else(is.finite(.x), .x, NA_real_)
    ))
}

## summarize_exceedances ----
# D7: counts of Exceeds / Below / Indeterminate for each group, plus the number
# of sites with at least one exceedance
summarize_exceedances <- function(exceedances, ...) {
  exceedances |>
    summarize(
      n_samples = n(),
      n_exceeds = sum(status == "Exceeds"),
      n_below = sum(status == "Below"),
      n_indeterminate = sum(status == "Indeterminate"),
      pct_exceeds = n_exceeds / n_samples,
      pct_indeterminate = n_indeterminate / n_samples,
      n_sites = n_distinct(site_id),
      n_sites_exceed = n_distinct(site_id[status == "Exceeds"]),
      pct_sites_exceed = n_sites_exceed / n_sites,
      .by = c(...)
    )
}

## build_sample_status ----
# one benchmark status per sample x analyte x benchmark, for the featured
# analytes plus "Total" (any featured analyte) and a "primary" pseudo-benchmark
# (either primary benchmark for the sample's water type, D6). When several
# results are combined the most serious status wins: Exceeds > Indeterminate > Below
status_rank <- c(Below = 1L, Indeterminate = 2L, Exceeds = 3L)

build_sample_status <- function(exceedances, benchmarks) {
  worst_status <- function(status) {
    names(status_rank)[max(status_rank[as.character(status)])]
  }

  keys <- c("site_type", "site_id", "date", "year", "sample_seq")

  exc <- exceedances |>
    filter(analyte %in% featured_analytes) |>
    left_join(
      distinct(benchmarks, benchmark, primary_for),
      join_by(benchmark)
    ) |>
    mutate(
      analyte = as.character(analyte),
      benchmark = as.character(benchmark),
      primary = as.character(site_type) == primary_for
    )

  primary <- exc |>
    filter(primary) |>
    summarize(status = worst_status(status), .by = c(all_of(keys), analyte)) |>
    mutate(benchmark = "primary")

  by_analyte <- bind_rows(
    select(exc, all_of(keys), analyte, benchmark, status),
    primary
  )

  total <- by_analyte |>
    summarize(
      status = worst_status(status),
      .by = c(all_of(keys), benchmark)
    ) |>
    mutate(analyte = "Total")

  bind_rows(by_analyte, total) |>
    mutate(
      analyte = factor(analyte, names(analyte_colors)),
      benchmark = factor(benchmark, c("primary", levels(benchmarks$benchmark))),
      status = factor(status, names(status_colors))
    )
}

## benchmark_label ----
benchmark_labels <- function(benchmarks) {
  benchmarks |>
    distinct(benchmark, short_label, label, primary_for) |>
    arrange(benchmark)
}


# Site popups ------------------------------------------------------------------

## build_site_popups ----
# D3: every analyte in a site's screen is listed, with non-detects noted
# returns one row per site with an HTML `popup` string
build_site_popups <- function(sites, site_analytes) {
  screens <- site_analytes |>
    mutate(
      line = if_else(
        n_detected > 0,
        sprintf(
          "<b>%s</b>: detected in %s of %s samples (max %s)",
          analyte,
          n_detected,
          n_samples,
          fmt_conc(max_result)
        ),
        sprintf(
          "%s: not detected (%s samples)",
          analyte,
          n_samples
        )
      )
    ) |>
    arrange(site_type, site_id, desc(n_detected > 0), analyte) |>
    summarize(
      screen = paste(line, collapse = "<br>"),
      .by = c(site_type, site_id)
    )

  sites |>
    left_join(screens, join_by(site_type, site_id)) |>
    mutate(
      location_note = if_else(
        location_blurred,
        "<br><i>Location approximate (private well)</i>",
        ""
      ),
      well_note = if_else(
        site_type == "Groundwater" & !is.na(well_depth),
        sprintf("<br>Well depth: %s ft", round(well_depth)),
        ""
      ),
      popup = sprintf(
        "<b>%s</b><br>%s County · %s watershed%s%s<br>%s samples, %s<hr style='margin:4px 0'>%s",
        site_label,
        county,
        wshed_name,
        well_note,
        location_note,
        n_samples,
        fmt_date_range(first_date, last_date),
        screen
      )
    ) |>
    select(site_type, site_id, popup)
}
