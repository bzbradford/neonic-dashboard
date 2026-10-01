## MAP DATA ##

# Builds the filtered data and map layer sources for the Explore page. Colors
# are computed here and passed to MapLibre as feature properties, so layer
# updates only need to swap data (set_source) rather than rebuild expressions.

# Filtering --------------------------------------------------------------------

#' @param df app_results or app_status (or anything with the same columns)
#' @param f list of filters: water, analyte, years, wells (and benchmark for status)
apply_filters <- function(df, f, analyte = f$analyte) {
  types <- if (f$water == "Both") site_types else f$water

  df <- df |>
    filter(
      site_type %in% types,
      analyte %in% !!analyte,
      between(year, f$years[1], f$years[2])
    )

  if (f$wells == "private") {
    df <- filter(df, site_type != "Groundwater" | private_well)
  } else if (f$wells == "monitoring") {
    df <- filter(df, site_type != "Groundwater" | !private_well)
  }

  if ("benchmark" %in% names(df)) {
    df <- filter(df, benchmark == f$benchmark)
  }

  df
}

#' @param sel NULL (statewide) or list(type = "county" | "wshed" | "site", key)
apply_selection <- function(df, sel) {
  if (is.null(sel)) {
    return(df)
  }
  switch(
    sel$type,
    county = filter(df, county == sel$key),
    wshed = filter(df, wshed_code == sel$key),
    site = filter(df, paste(site_type, site_id, sep = "|") == sel$key)
  )
}


# Area summaries ---------------------------------------------------------------

## area_stats ----
# one row per county/watershed with detection and exceedance stats, and a
# per-water-type tooltip line (so pooled "Both" values are never shown alone)
area_stats <- function(res, status, geo_col) {
  exc_by <- function(...) {
    status |>
      summarize(
        n_status = n(),
        n_exceed = sum(status == "Exceeds"),
        n_indet = sum(status == "Indeterminate"),
        .by = c(...)
      ) |>
      mutate(pct_exceed = n_exceed / n_status)
  }

  overall <- res |>
    summarize_detections(all_of(geo_col)) |>
    mutate(pct_sites_det = n_sites_detected / n_sites) |>
    left_join(exc_by(all_of(geo_col)), join_by(!!geo_col))

  lines <- res |>
    summarize_detections(all_of(geo_col), site_type) |>
    left_join(
      exc_by(all_of(geo_col), site_type),
      join_by(!!geo_col, site_type)
    ) |>
    arrange(site_type) |>
    mutate(
      line = sprintf(
        "<b>%s</b>: %s sites, %s samples<br>&nbsp;&nbsp;%s detected%s · %s exceed benchmark",
        site_type,
        fmt_n(n_sites),
        fmt_n(n_samples),
        fmt_pct(det_freq, 0),
        if_else(
          is.na(median_det),
          "",
          paste0(" (median ", fmt_conc(median_det), ")")
        ),
        fmt_pct(coalesce(pct_exceed, 0), 0)
      )
    ) |>
    summarize(lines = paste(line, collapse = "<br>"), .by = all_of(geo_col))

  overall |>
    left_join(lines, join_by(!!geo_col)) |>
    rename(key = all_of(geo_col))
}


# Color scales -----------------------------------------------------------------

## metric_scale ----
# fill palette, legend labels and legend colors for each map metric
metric_scale <- function(metric) {
  switch(
    metric,
    det_freq = ,
    pct_sites_det = list(
      pal = scales::col_numeric(freq_ramp, c(0, 1)),
      transform = identity,
      labels = c("0%", "25%", "50%", "75%", "100%"),
      colors = freq_ramp
    ),
    pct_exceed = list(
      pal = scales::col_numeric(conc_ramp, c(0, 0.5)),
      transform = \(x) pmin(x, 0.5),
      labels = c("0%", "25%", "≥ 50%"),
      colors = conc_ramp
    ),
    median_det = list(
      pal = scales::col_numeric(conc_ramp, c(-2, 1)),
      transform = \(x) pmin(pmax(log10(x), -2), 1),
      labels = c("≤ 0.01", "0.1", "1", "≥ 10 µg/L"),
      colors = conc_ramp
    )
  )
}

metric_label <- function(metric, analyte) {
  analyte_txt <- if (analyte == "Total") "any neonicotinoid" else analyte
  switch(
    metric,
    det_freq = paste("Samples with", analyte_txt, "detected"),
    pct_sites_det = paste("Sites with", analyte_txt, "detected"),
    median_det = paste(
      "Median",
      if (analyte == "Total") "combined total" else analyte,
      "detection"
    ),
    pct_exceed = paste("Samples exceeding benchmark,", analyte_txt)
  )
}


# Layer sources ----------------------------------------------------------------

## build_area_layer ----
#' @returns sf with key, fill, has_data, tooltip for a county/watershed layer
build_area_layer <- function(geo, res, status, metric) {
  layer <- geo_layers[[geo]]
  stats <- area_stats(res, status, layer$col)
  scale <- metric_scale(metric)

  layer$shapes |>
    left_join(layer$names, join_by(key)) |>
    left_join(stats, join_by(key)) |>
    mutate(
      has_data = !is.na(n_samples),
      value = .data[[metric]],
      fill = case_when(
        !has_data ~ no_data_color,
        is.na(value) ~ "#ffffff", # data, but no detections to take a median of
        .default = scale$pal(scale$transform(value))
      ),
      tooltip = if_else(
        has_data,
        paste0("<b>", name, "</b><br>", lines),
        paste0(
          "<b>",
          name,
          "</b><br>No monitoring data for the current filters"
        )
      )
    ) |>
    select(key, name, has_data, fill, tooltip)
}

## build_sel_layer ----
#' @param type "county", "wshed" or "site"
#' @param sel NULL or list(type, key)
#' @returns sf holding the selected feature if it is of this type, else empty
build_sel_layer <- function(type, sel) {
  k <- if (!is.null(sel) && sel$type == type) sel$key else character()
  if (type == "site") {
    filter(app_sites, site_key %in% k) |> select(site_key)
  } else {
    filter(geo_layers[[type]]$shapes, key %in% k)
  }
}

## build_site_layer ----
#' @param muted smaller points when shown on top of a choropleth
#' @returns sf of sites present in the filtered data, colored by status
build_site_layer <- function(res, status, analyte, muted = FALSE) {
  site_stats <- res |>
    summarize(
      n_samples = n(),
      n_detected = sum(detected),
      max_det = suppressWarnings(max(result, na.rm = TRUE)),
      .by = site_key
    )

  site_exc <- status |>
    mutate(site_key = paste(site_type, site_id, sep = "|")) |>
    summarize(n_exceed = sum(status == "Exceeds"), .by = site_key)

  analyte_txt <- if (analyte == "Total") "Any neonicotinoid" else analyte
  size <- if (muted) 0.7 else 1

  app_sites |>
    select(site_key, site_type, site_label, popup) |>
    inner_join(site_stats, join_by(site_key)) |>
    left_join(site_exc, join_by(site_key)) |>
    mutate(
      status = case_when(
        coalesce(n_exceed, 0) > 0 ~ "Exceeded benchmark",
        n_detected > 0 ~ "Detected",
        .default = "Not detected"
      ),
      color = site_status_colors[status],
      sort = match(status, rev(names(site_status_colors))),
      radius = if_else(site_type == "Surface water", 6, 4) * size,
      stroke = if_else(site_type == "Surface water", "#1f2328", "#ffffff"),
      tooltip = sprintf(
        "<b>%s</b><br>%s: %s<br>Detected in %s of %s samples%s%s",
        site_label,
        analyte_txt,
        status,
        n_detected,
        n_samples,
        if_else(n_detected > 0, paste0(" (max ", fmt_conc(max_det), ")"), ""),
        if_else(
          coalesce(n_exceed, 0) > 0,
          paste0("<br>", n_exceed, " samples exceeded benchmark"),
          ""
        )
      )
    ) |>
    arrange(sort) |>
    select(site_key, color, sort, radius, stroke, tooltip, popup)
}
