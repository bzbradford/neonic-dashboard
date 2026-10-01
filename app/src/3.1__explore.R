## EXPLORE ##

# Map + controls + selection panel. The map is rendered once; control changes
# swap layer data through maplibre_proxy() so the view (zoom/pan) is kept.
# Layer ids: county-*, wshed-* (fill, line, nodata, sel-casing, sel), sites,
# site-sel-casing, site-sel.

exploreUI <- function(id = "explore") {
  ns <- NS(id)

  layout_sidebar(
    fillable = TRUE,
    class = "p-0",

    # Sidebar ----
    sidebar = sidebar(
      width = 290,
      resizable = FALSE, # the resize handle lacks required ARIA attributes
      title = "Map options",

      # keyboard/screen-reader alternative to clicking the map
      selectizeInput(
        ns("find"),
        "Find a place",
        choices = "",
        options = list(
          placeholder = "County, watershed, or site",
          # x button to clear the selection (shown only when one is set). An
          # unnamed list, since Shiny appends its own a11y plugin to it
          plugins = list(
            list(
              name = "clear_button",
              options = list(title = "Clear selection")
            )
          )
        )
      ),

      radioButtons(
        ns("water"),
        "Water type",
        choices = water_choices,
        inline = TRUE
      ),
      conditionalPanel(
        "input.water == 'Both'",
        ns = ns,
        div(
          class = "note",
          "County and watershed colors pool both water types. Hover a unit to see each type separately. Larger outlined points are surface water sites."
        )
      ),

      radioButtons(ns("analyte"), "Analyte", choices = analyte_choices),

      radioButtons(
        ns("geo"),
        "Map areas",
        choices = geo_choices,
        inline = TRUE
      ),

      conditionalPanel(
        "input.geo != 'sites'",
        ns = ns,
        selectInput(ns("metric"), "Color areas by", choices = metric_choices),
        checkboxInput(ns("show_sites"), "Show sites", value = TRUE)
      ),

      selectInput(
        ns("benchmark"),
        tooltip(
          span("Benchmark", bs_icon("info-circle")),
          "Used for exceedance colors and counts. 'Primary' compares surface water to EPA aquatic life benchmarks and groundwater to proposed Wisconsin NR 140 standards."
        ),
        choices = benchmark_choices
      ),

      sliderInput(
        ns("years"),
        "Sample years",
        min = year_range[1],
        max = year_range[2],
        value = year_range,
        step = 1,
        sep = ""
      ),
      div(
        class = "note",
        style = "margin-top: -0.75rem;",
        actionLink(ns("recent_years"), "Use 2019 onward"),
        " (current 0.01 µg/L detection limits) · ",
        actionLink(ns("all_years"), "All years")
      ),

      conditionalPanel(
        "input.water != 'Surface water'",
        ns = ns,
        radioButtons(ns("wells"), "Wells", choices = well_choices)
      )
    ),

    # Main ----
    layout_columns(
      class = "explore-columns",
      col_widths = breakpoints(sm = 12, lg = c(7, 5)),
      gap = "0.75rem",

      ## Map ----
      card(
        full_screen = TRUE,
        class = "map-card",
        role = "region",
        `aria-label` = "Map",
        card_body(
          padding = 0,
          p(
            class = "visually-hidden",
            "Interactive map of monitoring results. Click a county, watershed or site to select it, or use the Find a place box in the map options. The selected place's results are summarized in the panel next to the map."
          ),
          maplibreOutput(ns("map"), height = "100%")
        )
      ),

      ## Selection panel ----
      card(
        class = "selection-card",
        role = "region",
        `aria-label` = "Selected place results",
        # announce selection and summary changes to screen readers
        card_header(
          `aria-live` = "polite",
          uiOutput(ns("sel_header"))
        ),
        card_body(
          div(`aria-live` = "polite", uiOutput(ns("sel_stats"))),
          navset_underline(
            id = ns("sel_tabs"),
            nav_panel(
              "Over time",
              div(
                role = "figure",
                `aria-label` = "Chart of individual sample results over time. The same results are listed in the Sites or Results tab.",
                plotlyOutput(ns("ts_plot"), height = "380px")
              ),
              div(
                class = "note",
                "Filled points are detections; open points are non-detects plotted at the detection limit. Dashed lines are benchmarks."
              )
            ),
            nav_panel(
              "By year",
              div(
                role = "figure",
                `aria-label` = "Bar chart of the share of samples with a detection in each year.",
                plotlyOutput(ns("annual_plot"), height = "380px")
              ),
              div(
                class = "note",
                "Share of samples with a detection each year; hover a bar for benchmark exceedances. Detection limits fell from 0.2–0.5 µg/L before 2015 to 0.01 µg/L from 2019, so earlier years undercount detections."
              )
            ),
            nav_panel(
              uiOutput(ns("table_tab_title"), inline = TRUE),
              value = "table",
              reactableOutput(ns("sel_table")),
              div(
                style = "margin-top: 0.5rem;",
                downloadButton(
                  ns("download"),
                  "Download results (CSV)",
                  class = "btn-sm btn-outline-secondary"
                )
              )
            )
          )
        )
      )
    )
  )
}


exploreServer <- function(id = "explore") {
  moduleServer(
    id = id,
    function(input, output, session) {
      ns <- session$ns
      proxy <- maplibre_proxy("map")

      # Reactive values ----

      rv <- reactiveValues(
        # NULL = statewide, else list(type = "county" | "wshed" | "site", key)
        sel = NULL,
        map_ready = FALSE
      )

      ## filters ----
      filters <- reactive({
        list(
          water = req(input$water),
          analyte = req(input$analyte),
          years = req(input$years),
          wells = input$wells %||% "all",
          benchmark = req(input$benchmark)
        )
      }) |>
        debounce(250)

      ## filtered data ----
      res_f <- reactive(apply_filters(app_results, filters()))
      status_f <- reactive(apply_filters(app_status, filters()))

      # all three analytes, for charts when "Any neonicotinoid" is selected
      res_f_all <- reactive({
        f <- filters()
        analytes <- if (f$analyte == "Total") featured_analytes else f$analyte
        apply_filters(app_results, f, analytes)
      })

      ## selection data ----
      sel_res <- reactive(apply_selection(res_f(), rv$sel))
      sel_status <- reactive(apply_selection(status_f(), rv$sel))
      sel_res_all <- reactive(apply_selection(res_f_all(), rv$sel))

      sel_name <- reactive({
        sel <- rv$sel
        if (is.null(sel)) {
          return("Statewide")
        }
        switch(
          sel$type,
          county = county_names$name[county_names$key == sel$key],
          wshed = wshed_names$name[wshed_names$key == sel$key],
          site = app_sites$site_label[app_sites$site_key == sel$key]
        )
      })

      # benchmark values to draw on time series (single analyte only)
      bm_values <- reactive({
        f <- filters()
        if (f$analyte == "Total") {
          return(NULL)
        }
        bm <- benchmarks |>
          filter(analyte == f$analyte) |>
          mutate(benchmark = as.character(benchmark))
        if (f$benchmark == "primary") {
          bm |> mutate(site_type = primary_for)
        } else {
          bm |>
            filter(benchmark == f$benchmark) |>
            crossing(site_type = site_types)
        }
      })

      # URL state ----
      # ?water=&analyte=&geo=&metric=&bm=&sel=county:Dane

      observeEvent(TRUE, once = TRUE, {
        q <- parseQueryString(session$clientData$url_search)
        set_if <- function(param, fn, id, choices) {
          val <- q[[param]]
          if (!is.null(val) && val %in% choices) fn(session, id, selected = val)
        }
        set_if("water", updateRadioButtons, "water", water_choices)
        set_if("analyte", updateRadioButtons, "analyte", analyte_choices)
        set_if("geo", updateRadioButtons, "geo", geo_choices)
        set_if("metric", updateSelectInput, "metric", metric_choices)
        set_if("bm", updateSelectInput, "benchmark", benchmark_choices)
        if (!is.null(q$sel)) {
          parts <- str_split_1(q$sel, ":")
          valid <- switch(
            parts[1],
            county = parts[2] %in% county_names$key,
            wshed = parts[2] %in% wshed_names$key,
            site = parts[2] %in% app_sites$site_key,
            FALSE
          )
          if (length(parts) == 2 && valid) {
            rv$sel <- list(type = parts[1], key = parts[2])
          }
        }
      })

      # query string for the Share button; the URL itself stays clean
      share_query <- reactive({
        sel <- rv$sel
        params <- list(
          water = input$water,
          analyte = input$analyte,
          geo = input$geo,
          metric = input$metric,
          bm = input$benchmark,
          sel = if (!is.null(sel)) paste0(sel$type, ":", sel$key)
        ) |>
          compact()
        paste(
          names(params),
          map_chr(params, URLencode, reserved = TRUE),
          sep = "=",
          collapse = "&"
        )
      })

      # Controls ----

      updateSelectizeInput(
        session = session,
        inputId = "find",
        choices = c("", find_choices),
        selected = "",
        server = TRUE
      )

      observeEvent(input$recent_years, {
        updateSliderInput(session, "years", value = c(2019, year_range[2]))
      })

      observeEvent(input$all_years, {
        updateSliderInput(session, "years", value = year_range)
      })

      # Map ----

      ## initial render ----
      output$map <- renderMaplibre({
        f <- isolate(filters())
        res <- isolate(res_f())
        status <- isolate(status_f())
        metric <- isolate(input$metric) %||% "det_freq"
        geo <- isolate(input$geo) %||% "county"

        # proxy messages sent before the map exists are dropped, so the
        # initial selection (e.g. from the URL) is drawn here
        sel <- isolate(rv$sel)

        vis <- \(g) if (geo == g) "visible" else "none"
        area_layer <- function(map, g) {
          src <- build_area_layer(g, res, status, metric)
          map |>
            add_fill_layer(
              id = paste0(g, "-fill"),
              source = src,
              fill_color = get_column("fill"),
              fill_opacity = 0.8,
              tooltip = "tooltip",
              visibility = vis(g)
            ) |>
            # layers below share the fill layer's source (named after its
            # layer id), so one set_source() on "-fill" updates them all
            add_line_layer(
              id = paste0(g, "-line"),
              source = paste0(g, "-fill"),
              line_color = "#8a8a86",
              line_width = 0.5,
              visibility = if (geo == g || (geo == "sites" && g == "county")) {
                "visible"
              } else {
                "none"
              }
            ) |>
            # no monitoring data: gray fill (set in build_area_layer) + dashed outline
            add_line_layer(
              id = paste0(g, "-nodata"),
              source = paste0(g, "-fill"),
              line_color = "#6b6a66",
              line_width = 1,
              line_dasharray = c(2, 2),
              filter = list("==", get_column("has_data"), FALSE),
              visibility = vis(g)
            )
        }

        # selection outline: a bright core over a dark casing so it stands
        # out on both the blue and red ramps. Highlight layers hold only the
        # selected feature and are updated with set_source() (mapgl ANDs a
        # set_filter() with the layer's initial filter, so filters can't be
        # swapped)
        sel_line <- function(map, g) {
          map |>
            add_line_layer(
              id = paste0(g, "-sel-casing"),
              source = build_sel_layer(g, sel),
              line_color = sel_colors$casing,
              line_width = 3.5
            ) |>
            add_line_layer(
              id = paste0(g, "-sel"),
              source = paste0(g, "-sel-casing"),
              line_color = sel_colors$core,
              line_width = 1.5
            )
        }

        sites_src <- build_site_layer(
          res,
          status,
          f$analyte,
          muted = geo != "sites"
        )

        maplibre(
          style = carto_style("positron"),
          bounds = wi_bbox,
          projection = "mercator",
          minZoom = 5,
          maxZoom = 14
        ) |>
          area_layer("county") |>
          area_layer("wshed") |>
          sel_line("county") |>
          sel_line("wshed") |>
          add_circle_layer(
            id = "sites",
            source = sites_src,
            circle_color = get_column("color"),
            circle_radius = get_column("radius"),
            circle_stroke_color = get_column("stroke"),
            circle_stroke_width = 1,
            circle_opacity = 0.9,
            circle_sort_key = get_column("sort"),
            tooltip = "tooltip",
            popup = "popup"
          ) |>
          # ring around the selected site: dark edges either side of the core
          add_circle_layer(
            id = "site-sel-casing",
            source = build_sel_layer("site", sel),
            circle_radius = 9,
            circle_color = "rgba(0,0,0,0)",
            circle_stroke_color = sel_colors$casing,
            circle_stroke_width = 7
          ) |>
          add_circle_layer(
            id = "site-sel",
            source = "site-sel-casing",
            circle_radius = 10,
            circle_color = "rgba(0,0,0,0)",
            circle_stroke_color = sel_colors$core,
            circle_stroke_width = 3
          ) |>
          add_navigation_control(show_compass = FALSE) |>
          add_fullscreen_control() |>
          add_map_legends(f, geo, metric)
      })

      ## legends ----
      # mapgl's default legend background is 50% white
      legend_bg <- legend_style(background_opacity = 0.85)

      add_map_legends <- function(map, f, geo, metric) {
        if (geo != "sites") {
          scale <- metric_scale(metric)
          map <- map |>
            add_continuous_legend(
              legend_title = paste0(
                metric_label(metric, f$analyte),
                "<br><span class='legend-note'>Gray dashed = no monitoring data</span>"
              ),
              values = scale$labels,
              colors = scale$colors,
              position = "bottom-left",
              add = TRUE,
              unique_id = "legend-area",
              style = legend_bg
            )
        }
        map |>
          add_categorical_legend(
            legend_title = if (f$water == "Both") {
              "Sites (outlined = surface water)"
            } else {
              "Sites"
            },
            values = names(site_status_colors),
            colors = unname(site_status_colors),
            patch_shape = "circle",
            position = "top-left",
            add = TRUE,
            unique_id = "legend-sites",
            style = legend_bg
          )
      }

      ## update layers ----
      observeEvent(
        list(res_f(), status_f(), input$geo, input$metric, input$show_sites),
        ignoreInit = TRUE,
        {
          f <- filters()
          geo <- input$geo
          metric <- input$metric

          # area layer: only the visible one is rebuilt
          for (g in names(geo_layers)) {
            vis <- if (geo == g) "visible" else "none"
            for (suffix in c("-fill", "-nodata")) {
              proxy |> set_layout_property(paste0(g, suffix), "visibility", vis)
            }
            line_vis <- if (geo == g || (geo == "sites" && g == "county")) {
              "visible"
            } else {
              "none"
            }
            proxy |>
              set_layout_property(paste0(g, "-line"), "visibility", line_vis)
          }
          if (geo != "sites") {
            src <- build_area_layer(geo, res_f(), status_f(), metric)
            proxy |> set_source(paste0(geo, "-fill"), src)
          }

          # sites
          show_sites <- geo == "sites" || isTRUE(input$show_sites)
          proxy |>
            set_layout_property(
              "sites",
              "visibility",
              if (show_sites) "visible" else "none"
            ) |>
            set_source(
              "sites",
              build_site_layer(
                res_f(),
                status_f(),
                f$analyte,
                muted = geo != "sites"
              )
            )

          proxy |>
            clear_legend() |>
            add_map_legends(f, geo, metric)
        }
      )

      ## selection highlight ----
      observe({
        sel <- rv$sel
        proxy |>
          set_source("county-sel", build_sel_layer("county", sel)) |>
          set_source("wshed-sel", build_sel_layer("wshed", sel)) |>
          set_source("site-sel", build_sel_layer("site", sel))
      })

      ## map clicks ----
      observeEvent(input$map_feature_click, {
        f <- input$map_feature_click
        props <- f$properties
        # highlight layers sit on top, so clicks on the selected place
        # report them rather than the fill or site layer
        new_sel <- switch(
          f$layer,
          "county-fill" = ,
          "county-sel" = ,
          "county-sel-casing" = list(type = "county", key = props$key),
          "wshed-fill" = ,
          "wshed-sel" = ,
          "wshed-sel-casing" = list(type = "wshed", key = props$key),
          "sites" = ,
          "site-sel" = ,
          "site-sel-casing" = list(type = "site", key = props$site_key),
          NULL # basemap features are ignored
        )
        req(new_sel)
        # clicking the active selection again clears it
        if (identical(new_sel, rv$sel)) rv$sel <- NULL else rv$sel <- new_sel
      })

      ## zoom_to ----
      # moves the map to a selection; no animation if the user prefers reduced motion
      zoom_to <- function(sel) {
        reduced <- isTRUE(session$rootScope()$input$reduced_motion)
        if (sel$type == "site") {
          site <- filter(app_sites, site_key == sel$key)
          center <- c(site$map_lon, site$map_lat)
          if (reduced) {
            proxy |> set_view(center = center, zoom = 10)
          } else {
            proxy |> fly_to(center = center, zoom = 10)
          }
        } else {
          shape <- filter(geo_layers[[sel$type]]$shapes, key == sel$key)
          proxy |>
            fit_bounds(
              as.numeric(st_bbox(shape)),
              animate = !reduced,
              padding = 40
            )
        }
      }

      ## table row clicks ----
      observeEvent(input$site_row, {
        rv$sel <- list(type = "site", key = input$site_row)
        zoom_to(rv$sel)
      })

      ## find a place ----
      observeEvent(input$find, ignoreInit = TRUE, {
        if (input$find == "") {
          rv$sel <- NULL
          return()
        }
        parts <- str_split_1(input$find, ":")
        new_sel <- list(type = parts[1], key = parts[2])
        # ignore updates that just mirror a selection made elsewhere
        if (identical(new_sel, rv$sel)) {
          return()
        }
        rv$sel <- new_sel
        zoom_to(new_sel)
      })

      # keep the find box in sync with map and table selections
      observe({
        sel <- rv$sel
        value <- if (is.null(sel)) "" else paste0(sel$type, ":", sel$key)
        if (!identical(isolate(input$find), value)) {
          updateSelectizeInput(session, "find", selected = value)
        }
      })

      observeEvent(input$clear_sel, {
        rv$sel <- NULL
      })

      # Selection panel ----

      output$sel_header <- renderUI({
        sel <- rv$sel
        f <- filters()
        types <- if (f$water == "Both") {
          "Surface water & groundwater"
        } else {
          f$water
        }
        analyte_txt <- names(analyte_choices)[analyte_choices == f$analyte]
        div(
          class = "sel-header",
          div(
            h2(class = "h5 mb-0", sel_name()),
            div(
              class = "note",
              sprintf(
                "%s · %s · %s–%s",
                types,
                analyte_txt,
                f$years[1],
                f$years[2]
              )
            )
          ),
          if (!is.null(sel)) {
            actionButton(
              ns("clear_sel"),
              "Statewide",
              icon = icon("xmark"),
              class = "btn-sm btn-outline-secondary"
            )
          }
        )
      })

      output$sel_stats <- renderUI({
        res <- sel_res()
        status <- sel_status()
        f <- filters()
        if (nrow(res) == 0) {
          return(div(
            class = "note",
            "No samples match the current filters for this selection."
          ))
        }
        s <- summarize_detections(res)
        e <- summarize(
          status,
          n = n(),
          n_exceed = sum(status == "Exceeds"),
          n_indet = sum(status == "Indeterminate")
        )
        tips <- stat_tooltips(s, e, f, unique(as.character(res$site_type)))
        # tooltips also open on keyboard focus (bslib makes the box focusable)
        stat <- function(value, label, sub = NULL, tip) {
          tooltip(
            div(
              class = "stat",
              div(class = "stat-value", value),
              div(class = "stat-label", label),
              if (!is.null(sub)) div(class = "stat-sub", sub)
            ),
            tip,
            placement = "bottom",
            options = list(customClass = "stat-tip")
          )
        }
        div(
          class = "stat-row",
          stat(
            fmt_n(s$n_samples),
            "samples",
            paste(fmt_n(s$n_sites), if (s$n_sites == 1) "site" else "sites"),
            tips$samples
          ),
          stat(
            fmt_pct(s$det_freq, 0),
            "detected",
            paste(fmt_n(s$n_detected), "samples"),
            tips$detected
          ),
          stat(
            if (is.na(s$median_det)) {
              "–"
            } else {
              fmt_conc(s$median_det, units = FALSE)
            },
            "median µg/L",
            if (!is.na(s$max_det)) {
              paste("max", fmt_conc(s$max_det, units = FALSE))
            },
            tips$median
          ),
          stat(
            fmt_pct(e$n_exceed / e$n, 0),
            "exceed benchmark",
            if (e$n_indet > 0) paste(fmt_n(e$n_indet), "indeterminate"),
            tips$exceed
          )
        )
      })

      output$ts_plot <- renderPlotly({
        d <- sel_res_all()
        validate(need(
          nrow(d) > 0,
          "No samples match the current filters for this selection."
        ))
        plot_timeseries(d, bm_values())
      })

      output$annual_plot <- renderPlotly({
        d <- sel_res()
        validate(need(
          nrow(d) > 0,
          "No samples match the current filters for this selection."
        ))
        plot_annual(d, sel_status(), benchmark_short(filters()$benchmark))
      })

      output$table_tab_title <- renderUI({
        if (identical(rv$sel$type, "site")) "Results" else "Sites"
      })

      output$sel_table <- renderReactable({
        sel <- rv$sel
        if (identical(sel$type, "site")) {
          site_results_table(sel$key)
        } else {
          res <- sel_res()
          validate(need(nrow(res) > 0, "No sites match the current filters."))
          sites_table(res, sel_status(), ns("site_row"))
        }
      })

      output$download <- downloadHandler(
        filename = function() {
          paste0(
            "neonic-results-",
            str_replace_all(tolower(sel_name()), "[^a-z0-9]+", "-"),
            ".csv"
          )
        },
        content = function(file) {
          keys <- sel_res() |> distinct(site_type, site_id)
          results |>
            semi_join(keys, join_by(site_type, site_id)) |>
            filter(between(year, filters()$years[1], filters()$years[2])) |>
            left_join(
              st_drop_geometry(sites) |>
                select(
                  site_type,
                  site_id,
                  site_label,
                  county,
                  wshed_name,
                  map_lat,
                  map_lon,
                  location_blurred
                ),
              join_by(site_type, site_id)
            ) |>
            select(
              site_type,
              site_id,
              site_label,
              county,
              wshed_name,
              map_lat,
              map_lon,
              location_blurred,
              date,
              sample_seq,
              analyte,
              detected,
              result,
              dl
            ) |>
            write_csv(file, na = "")
        }
      )

      share_query
    }
  )
}


# Stat tooltips ----------------------------------------------------------------

## benchmark_short ----
# short benchmark name for chart hover text
benchmark_short <- function(benchmark) {
  switch(
    benchmark,
    primary = "primary benchmark",
    aquatic_acute = "EPA aquatic acute benchmark",
    aquatic_chronic = "EPA aquatic chronic benchmark",
    proposed_es = "proposed WI ES",
    proposed_pal = "proposed WI PAL"
  )
}

## describe_benchmark ----
# which benchmark the exceedance stat uses, with values for a single analyte
describe_benchmark <- function(benchmark, analyte, types) {
  # e.g. " (acute 11 µg/L, chronic 0.05 µg/L)"
  values <- function(ids, names = NULL) {
    if (analyte == "Total") {
      return("")
    }
    v <- benchmarks$value[match(
      paste(analyte, ids),
      paste(benchmarks$analyte, benchmarks$benchmark)
    )]
    v <- fmt_conc(v)
    if (!is.null(names)) {
      v <- paste(names, v)
    }
    paste0(" (", paste(v, collapse = ", "), ")")
  }

  if (benchmark != "primary") {
    lbl <- as.character(benchmarks$label[benchmarks$benchmark == benchmark][1])
    return(paste0(lbl, values(benchmark), "."))
  }

  by_type <- c(
    "Surface water" = paste0(
      "Surface water uses the EPA aquatic life benchmarks for invertebrates",
      values(c("aquatic_acute", "aquatic_chronic"), c("acute", "chronic"))
    ),
    "Groundwater" = paste0(
      "Groundwater uses the proposed Wisconsin NR 140 standards",
      values(c("proposed_es", "proposed_pal"), c("ES", "PAL"))
    )
  )
  types <- intersect(names(by_type), types)
  lower <- c("Surface water" = "chronic", "Groundwater" = "PAL")[types]
  paste0(
    "Primary, by water type. ",
    paste0(by_type[types], ".", collapse = " "),
    " A sample counts if it reaches either value, so in practice the lower one (",
    paste(lower, collapse = " or "),
    ") decides."
  )
}

## stat_tooltips ----
#' @param s summarize_detections() of the selection
#' @param e exceedance counts: n, n_exceed, n_indet
#' @param f current filters
#' @param types water types present in the selection
#' @returns list of tooltip contents for the four selection stats
stat_tooltips <- function(s, e, f, types) {
  total <- f$analyte == "Total"
  analyte_txt <- if (total) "any neonicotinoid" else f$analyte
  pct <- \(x) fmt_pct(x, if (x > 0 && x < 0.1) 1 else 0)

  samples <- tagList(
    p(sprintf(
      "Water samples matching the current filters (water type, years%s) that were tested for %s. One sample is one collection at one site and date.",
      if (f$wells == "all") "" else ", wells",
      analyte_txt
    )),
    p(sprintf(
      "%s %s contributed. Sites sampled more often weigh more heavily in the percentages.",
      fmt_n(s$n_sites),
      if (s$n_sites == 1) "site" else "sites"
    ))
  )

  detected <- tagList(
    p(sprintf(
      "%s of %s samples (%s) had %s detected, at or above the lab's detection limit. %s of %s sites had at least one detection.",
      fmt_n(s$n_detected),
      fmt_n(s$n_samples),
      pct(s$det_freq),
      analyte_txt,
      fmt_n(s$n_sites_detected),
      fmt_n(s$n_sites)
    )),
    if (f$years[1] < 2019) {
      p(
        "A non-detect doesn't mean none was present. Detection limits fell from 0.2–0.5 µg/L before 2015 to 0.01 µg/L from 2019, so ranges that include earlier years understate detection."
      )
    }
  )

  median <- if (s$n_detected == 0) {
    p("No detections, so there are no concentrations to summarize.")
  } else {
    tagList(
      p(sprintf(
        "Median of the %s detected concentrations; the highest was %s. Non-detects are left out, so this is a typical level when %s is found, not in a typical sample.",
        fmt_n(s$n_detected),
        fmt_conc(s$max_det),
        analyte_txt
      )),
      if (total) {
        p(
          "A sample's concentration is the sum of all neonicotinoids detected in it."
        )
      }
    )
  }

  exceed <- tagList(
    p(sprintf(
      "%s of all %s samples (%s) were at or above the benchmark. This is a share of all samples, including non-detects, not just of detections.",
      fmt_n(e$n_exceed),
      fmt_n(e$n),
      pct(e$n_exceed / e$n)
    )),
    p(
      strong("Benchmark: "),
      describe_benchmark(f$benchmark, f$analyte, types)
    ),
    if (total) {
      p(
        "Each neonicotinoid is compared with its own benchmark; a sample counts if imidacloprid, clothianidin or thiamethoxam reaches it."
      )
    },
    p(paste0(
      "Indeterminate samples are non-detects whose detection limit was above the benchmark, so whether they exceeded is unknown. They count in the total but not as exceedances",
      if (e$n_indet > 0) {
        sprintf(
          "; %s samples (%s) are indeterminate here, so the true share could be as high as %s.",
          fmt_n(e$n_indet),
          pct(e$n_indet / e$n),
          pct((e$n_exceed + e$n_indet) / e$n)
        )
      } else {
        ". There are none here."
      }
    )),
    p(
      "Benchmarks are screening values: the EPA aquatic life benchmarks are not regulatory limits, and the Wisconsin groundwater standards are proposed."
    )
  )

  list(
    samples = samples,
    detected = detected,
    median = median,
    exceed = exceed
  )
}
