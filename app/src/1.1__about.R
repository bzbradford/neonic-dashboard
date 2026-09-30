## ABOUT ##

# Landing page: plain-language framing, headline stat cards, how to read the
# data, benchmarks, and methods. Copy is placeholder for Ben to refine.

stat_cards <- function(type) {
  s <- filter(headline_stats, site_type == type)

  layout_column_wrap(
    width = 1 / 2,
    heights_equal = "row",
    value_box(
      title = "Samples",
      value = fmt_n(s$n_samples),
      p(fmt_n(s$n_sites), if (type == "Groundwater") "wells" else "stream sites", "·", s$years),
      theme = value_box_theme(bg = "#ffffff", fg = brand$text)
    ),
    value_box(
      title = "Any neonicotinoid detected",
      value = fmt_pct(s$pct_detected, 0),
      p("of samples"),
      theme = value_box_theme(bg = "#ffffff", fg = brand$text)
    ),
    value_box(
      title = "Most often detected",
      value = s$top_analyte,
      p(fmt_pct(s$top_freq, 0), "of samples"),
      theme = value_box_theme(bg = "#ffffff", fg = brand$text)
    ),
    value_box(
      title = "Exceeded a benchmark",
      value = fmt_pct(s$pct_exceed, 0),
      p(
        "of samples, vs.",
        if (type == "Groundwater") "proposed NR 140 standards" else "EPA aquatic life benchmarks"
      ),
      theme = value_box_theme(bg = "#ffffff", fg = brand$text)
    )
  )
}

benchmark_table <- function() {
  df <- benchmarks |>
    filter(analyte %in% c(featured_analytes, "Acetamiprid")) |>
    mutate(analyte = as.character(analyte), value = fmt_conc(value, units = FALSE)) |>
    select(analyte, short_label, value) |>
    pivot_wider(names_from = short_label, values_from = value)

  reactable(
    df,
    compact = TRUE,
    sortable = FALSE,
    defaultColDef = colDef(na = "–", align = "right"),
    columns = list(analyte = colDef("Analyte (µg/L)", align = "left", minWidth = 130)),
    columnGroups = list(
      colGroup("EPA aquatic life (invertebrates)", c("Aquatic acute", "Aquatic chronic")),
      colGroup("Proposed WI groundwater (NR 140)", c("Proposed ES", "Proposed PAL"))
    )
  )
}

aboutUI <- function() {
  n_nd <- function(a) sum(results$analyte == a)

  div(
    class = "page-content",

    # Hero ----
    div(
      class = "hero",
      h1("Neonicotinoids in Wisconsin Waters"),
      p(
        class = "lead",
        "Neonicotinoids are the most widely used class of insecticides, applied mostly as seed coatings on corn and soybeans. They dissolve easily in water, so they can move from fields into groundwater and streams, where even low concentrations can harm aquatic insects."
      ),
      p(
        "The Wisconsin Department of Agriculture, Trade and Consumer Protection (DATCP) has tested streams and wells across the state for neonicotinoids since 2006. Many small Wisconsin streams are fed largely by groundwater, so the two are closely linked: what reaches shallow groundwater under farm fields can end up in nearby streams."
      ),
      div(
        class = "hero-buttons",
        actionButton("go_explore", "Explore the map", icon = icon("map"), class = "btn-primary"),
        actionButton("go_summary", "Read the data summary", icon = icon("chart-column"), class = "btn-outline-primary")
      )
    ),

    # Stat cards ----
    layout_columns(
      col_widths = breakpoints(sm = 12, lg = c(6, 6)),
      card(
        card_header(bs_icon("water"), "Surface water"),
        stat_cards("Surface water")
      ),
      card(
        card_header(bs_icon("moisture"), "Groundwater"),
        stat_cards("Groundwater")
      )
    ),

    # How to read ----
    layout_columns(
      col_widths = breakpoints(sm = 12, lg = c(6, 6)),
      card(
        card_header("How to read this data"),
        markdown(paste(
          "- **Detection:** the lab measured a neonicotinoid above its *detection limit*, the lowest concentration it can reliably measure. A non-detect means the concentration, if any, was below that limit, not that it was zero.",
          "- **Detection limits changed.** Early samples (before 2015) could only detect concentrations above about 0.2–0.5 µg/L; since 2019 the limit is 0.01 µg/L. More detections in recent years partly reflect better lab methods.",
          "- **Benchmarks** are concentrations above which harm is possible. Exceeding one is a signal for concern, not proof of harm. Where a non-detect's detection limit was above a benchmark, we can't tell whether it exceeded it, so it is counted as *indeterminate*.",
          "- **Private well locations** are shown at approximate positions (within about 1 km), always within the correct county and watershed.",
          "- **Units:** all concentrations are micrograms per liter (µg/L), equivalent to parts per billion (ppb).",
          sep = "\n"
        ))
      ),
      card(
        card_header("Benchmarks"),
        benchmark_table(),
        markdown(paste(
          "**EPA aquatic life benchmarks** ([source](https://www.epa.gov/pesticide-science-and-assessing-pesticide-risks/aquatic-life-benchmarks-and-ecological-risk)) estimate concentrations harmful to freshwater invertebrates from short-term (*acute*) or long-term (*chronic*) exposure. They apply to surface water.",
          "",
          "**Proposed Wisconsin groundwater standards** ([NR 140, Cycle 13 review](https://dnr.wisconsin.gov/topic/Groundwater/NR140.html)) include an *enforcement standard* (ES) and a lower *preventive action limit* (PAL). They are proposed and not yet in effect.",
          "",
          "By default, surface water is compared to the aquatic benchmarks and groundwater to the proposed NR 140 standards; other comparisons are available on the Explore page.",
          sep = "\n"
        ))
      )
    ),

    # Methods ----
    card(
      card_header("About the data"),
      markdown(paste(
        sprintf(
          "Samples were analyzed for six neonicotinoids. This dashboard focuses on the three found most often: **imidacloprid, clothianidin and thiamethoxam**. **Dinotefuran** was detected in only %s of %s samples, and **acetamiprid** (%s samples) and **thiacloprid** (%s samples) were screened for but never detected. Every analyte tested at a site is listed in that site's map popup.",
          sum(results$detected & results$analyte == "Dinotefuran"),
          fmt_n(n_nd("Dinotefuran")),
          fmt_n(n_nd("Acetamiprid")),
          fmt_n(n_nd("Thiacloprid"))
        ),
        "",
        "**Methods notes.** Concentration summaries (median, maximum) use detected results only. *Any neonicotinoid* means at least one of the analytes was detected in a sample; its concentration is the sum of all detected neonicotinoids (non-detects counted as zero). Surface water and groundwater are summarized separately except where the map is set to show both, in which case hover text breaks results out by water type.",
        "",
        sprintf(
          "**Data source:** Wisconsin Department of Agriculture, Trade and Consumer Protection (DATCP) surface water and groundwater monitoring, %s to %s. Dashboard data last updated %s.",
          format(min(results$date), "%B %Y"),
          format(last_sample_date, "%B %Y"),
          last_updated
        ),
        sep = "\n"
      ))
    ),

    site_footer()
  )
}
