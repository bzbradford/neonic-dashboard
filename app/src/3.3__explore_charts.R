## EXPLORE CHARTS ##

# Plotly charts and reactable tables for the Explore page selection panel.
# Surface water and groundwater are drawn as separate stacked panels, never
# pooled into one series.

# Shared -----------------------------------------------------------------------

plotly_config <- function(p) {
  p |>
    config(
      displaylogo = FALSE,
      modeBarButtonsToRemove = c("lasso2d", "select2d", "autoScale2d")
    ) |>
    layout(
      font = list(family = "Red Hat Text, sans-serif", color = brand$text),
      hoverlabel = list(font = list(family = "Red Hat Text, sans-serif")),
      legend = list(orientation = "h", x = 0, y = 1.12, yanchor = "bottom"),
      margin = list(l = 60, r = 20, t = 30, b = 30)
    )
}

# stack one plot per water type (shared x axis) with type labels
stack_by_type <- function(d, plot_fn, ...) {
  types <- intersect(site_types, unique(as.character(d$site_type)))
  if (length(types) == 0) {
    return(
      plotly_empty() |>
        layout(
          title = list(
            text = "No data for the current selection",
            font = list(size = 14)
          )
        )
    )
  }
  plots <- map(seq_along(types), \(i) {
    plot_fn(filter(d, site_type == types[i]), show_legend = i == 1, ...) |>
      layout(
        annotations = list(list(
          text = paste0("<b>", types[i], "</b>"),
          x = 0,
          xref = "paper",
          xanchor = "left",
          y = 1,
          yref = "paper",
          yanchor = "bottom",
          showarrow = FALSE,
          font = list(size = 13)
        ))
      )
  })
  if (length(plots) == 1) {
    return(plots[[1]])
  }
  subplot(
    plots,
    nrows = length(plots),
    shareX = TRUE,
    titleY = TRUE,
    margin = 0.06
  )
}


# Time series ------------------------------------------------------------------

## ts_panel ----
# results over time: filled = detection, open = non-detect plotted at its DL,
# dashed lines = benchmarks
ts_panel <- function(d, show_legend = TRUE, bm_values = NULL) {
  d <- d |>
    mutate(
      y = coalesce(result, dl),
      text = sprintf(
        "%s<br>%s: %s",
        format(date, "%b %d, %Y"),
        analyte,
        if_else(
          detected,
          fmt_conc(result),
          paste0("not detected (< ", fmt_conc(dl), ")")
        )
      )
    )

  p <- plot_ly()
  for (a in intersect(names(analyte_colors), unique(as.character(d$analyte)))) {
    col <- analyte_colors[[a]]
    det <- filter(d, analyte == a, detected)
    nd <- filter(d, analyte == a, !detected)
    if (nrow(nd) > 0) {
      p <- p |>
        add_trace(
          data = nd,
          x = ~date,
          y = ~y,
          text = ~text,
          type = "scattergl",
          mode = "markers",
          hoverinfo = "text",
          name = paste(a, "(not detected)"),
          legendgroup = paste(a, "nd"),
          showlegend = show_legend,
          marker = list(
            symbol = "circle-open",
            color = col,
            size = 6,
            opacity = 0.5
          )
        )
    }
    if (nrow(det) > 0) {
      p <- p |>
        add_trace(
          data = det,
          x = ~date,
          y = ~y,
          text = ~text,
          type = "scattergl",
          mode = "markers",
          hoverinfo = "text",
          name = a,
          legendgroup = a,
          showlegend = show_legend,
          marker = list(
            color = col,
            size = 8,
            opacity = 0.85,
            line = list(color = "white", width = 1)
          )
        )
    }
  }

  # benchmarks within (or near) the data range
  if (!is.null(bm_values) && nrow(bm_values) > 0 && nrow(d) > 0) {
    y_rng <- range(d$y, na.rm = TRUE)
    bm <- filter(bm_values, value <= y_rng[2] * 10, value >= y_rng[1] / 10)
    if (nrow(bm) > 0) {
      p <- p |>
        layout(
          shapes = map(bm$value, \(v) {
            list(
              type = "line",
              xref = "paper",
              x0 = 0,
              x1 = 1,
              y0 = v,
              y1 = v,
              line = list(color = brand$text, dash = "dash", width = 1)
            )
          }),
          annotations = map2(bm$value, bm$short_label, \(v, lbl) {
            list(
              text = paste0(lbl, " (", fmt_conc(v), ")"),
              x = 1,
              xref = "paper",
              xanchor = "right",
              y = log10(v),
              yanchor = "bottom",
              showarrow = FALSE,
              font = list(size = 10, color = brand$text),
              bgcolor = "rgba(255,255,255,0.8)"
            )
          })
        )
    }
  }

  p |>
    layout(
      xaxis = list(title = ""),
      yaxis = list(
        type = "log",
        title = "µg/L",
        exponentformat = "none",
        dtick = 1
      )
    )
}

## plot_timeseries ----
plot_timeseries <- function(d, bm_values = NULL) {
  stack_by_type(d, \(dd, show_legend) {
    bm <- if (is.null(bm_values)) {
      NULL
    } else {
      filter(bm_values, site_type == first(dd$site_type))
    }
    ts_panel(dd, show_legend, bm)
  }) |>
    plotly_config()
}


# Detection frequency by year --------------------------------------------------

## annual_panel ----
annual_panel <- function(d, show_legend = TRUE) {
  a <- summarize_detections(d, year, analyte) |>
    mutate(
      text = sprintf(
        "%s: %s of %s samples (%s)",
        year,
        n_detected,
        n_samples,
        fmt_pct(det_freq, 0)
      )
    )

  p <- plot_ly()
  for (an in intersect(
    names(analyte_colors),
    unique(as.character(a$analyte))
  )) {
    p <- p |>
      add_bars(
        data = filter(a, analyte == an),
        x = ~year,
        y = ~det_freq,
        text = ~text,
        hoverinfo = "text",
        textposition = "none",
        name = if (an == "Total") "Any neonicotinoid" else an,
        legendgroup = an,
        showlegend = show_legend,
        marker = list(color = analyte_colors[[an]])
      )
  }
  p |>
    layout(
      barmode = "group",
      xaxis = list(title = "", dtick = 2),
      yaxis = list(title = "Detected", tickformat = ".0%", rangemode = "tozero")
    )
}

plot_annual <- function(d) {
  stack_by_type(d, annual_panel) |>
    plotly_config()
}


# Tables -----------------------------------------------------------------------

## sites_table ----
# sites within an area selection; clicking a row selects that site
sites_table <- function(res, status, input_id) {
  exc <- status |>
    mutate(site_key = paste(site_type, site_id, sep = "|")) |>
    summarize(n_exceed = sum(status == "Exceeds"), .by = site_key)

  df <- res |>
    summarize(
      n_samples = n(),
      n_detected = sum(detected),
      max_det = suppressWarnings(max(result, na.rm = TRUE)),
      last = max(date),
      .by = c(site_key, site_type)
    ) |>
    mutate(max_det = if_else(is.finite(max_det), max_det, NA_real_)) |>
    left_join(exc, join_by(site_key)) |>
    left_join(
      st_drop_geometry(app_sites) |> select(site_key, site_label),
      join_by(site_key)
    ) |>
    arrange(desc(coalesce(n_exceed, 0)), desc(n_detected)) |>
    mutate(
      site_type = if_else(site_type == "Surface water", "Surface", "Ground")
    ) |>
    select(
      site_key,
      site_label,
      site_type,
      n_samples,
      n_detected,
      max_det,
      n_exceed,
      last
    )

  reactable(
    df,
    compact = TRUE,
    searchable = TRUE,
    highlight = TRUE,
    defaultPageSize = 10,
    style = list(fontSize = "0.8rem"),
    columns = list(
      site_key = colDef(show = FALSE),
      # site names are buttons so the table is keyboard accessible
      site_label = colDef("Site", minWidth = 170, cell = \(value, index) {
        tags$button(
          type = "button",
          class = "btn btn-link btn-sm p-0 text-start site-link",
          title = "Select this site",
          onclick = sprintf(
            "Shiny.setInputValue('%s', '%s', {priority: 'event'})",
            input_id,
            df$site_key[index]
          ),
          value
        )
      }),
      site_type = colDef("Water", minWidth = 65),
      n_samples = colDef("Samples", minWidth = 65),
      n_detected = colDef("Detects", minWidth = 60),
      max_det = colDef("Max µg/L", minWidth = 70, cell = \(v) {
        if (is.na(v)) "–" else fmt_conc(v, units = FALSE)
      }),
      n_exceed = colDef("Exceed", minWidth = 60, na = "0"),
      last = colDef("Last", minWidth = 85, format = colFormat(date = TRUE))
    )
  )
}

## site_results_table ----
# every result for one site: all six analytes in its screen, NDs shown with DL
site_results_table <- function(site_key) {
  key <- str_split_1(site_key, fixed("|"))

  df <- results |>
    filter(site_type == key[1], site_id == key[2]) |>
    mutate(
      value = if_else(
        detected,
        fmt_conc(result, units = FALSE),
        paste0("ND (<", fmt_conc(dl, units = FALSE), ")")
      ),
      date_lbl = if_else(
        sample_seq > 1,
        paste0(date, " (", sample_seq, ")"),
        as.character(date)
      )
    ) |>
    select(date_lbl, analyte, value) |>
    pivot_wider(names_from = analyte, values_from = value) |>
    arrange(desc(date_lbl))

  analyte_cols <- setdiff(names(df), "date_lbl")

  reactable(
    df,
    compact = TRUE,
    defaultPageSize = 10,
    style = list(fontSize = "0.8rem"),
    columns = c(
      list(date_lbl = colDef("Date", minWidth = 110)),
      set_names(
        map(analyte_cols, \(a) {
          colDef(
            a,
            minWidth = 95,
            na = "–",
            style = \(v) {
              if (!is.na(v) && !startsWith(v, "ND")) {
                list(fontWeight = 600, color = brand$text)
              } else {
                list(color = brand$muted)
              }
            }
          )
        }),
        analyte_cols
      )
    )
  )
}
