## EXPLORE ##

# Map + controls + selection panel. The map is rendered once; control changes
# swap layer data through maplibre_proxy() so the view (zoom/pan) is kept.
# Layer ids: county-*, wshed-* (fill, line, nodata, sel), sites, site-sel.

exploreUI <- function(id = "explore") {
  ns <- NS(id)

  layout_sidebar(
    fillable = TRUE,
    class = "p-0",

    # Sidebar ----
    sidebar = sidebar(
      width = 290,
      title = "Map options",

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
      col_widths = breakpoints(sm = 12, lg = c(7, 5)),
      gap = "0.75rem",

      ## Map ----
      card(
        full_screen = TRUE,
        class = "map-card",
        card_body(
          padding = 0,
          maplibreOutput(ns("map"), height = "100%")
        )
      ),

      ## Selection panel ----
      card(
        class = "selection-card",
        card_header(uiOutput(ns("sel_header"))),
        card_body(
          uiOutput(ns("sel_stats")),
          navset_underline(
            id = ns("sel_tabs"),
            nav_panel(
              "Over time",
              plotlyOutput(ns("ts_plot"), height = "380px"),
              div(
                class = "note",
                "Filled points are detections; open points are non-detects plotted at the detection limit. Dashed lines are benchmarks."
              )
            ),
            nav_panel(
              "By year",
              plotlyOutput(ns("annual_plot"), height = "380px"),
              div(
                class = "note",
                "Share of samples with a detection each year. Detection limits fell from 0.2–0.5 µg/L before 2015 to 0.01 µg/L from 2019, so earlier years undercount detections."
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

      observe({
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
        query <- paste0(
          "?",
          paste(
            names(params),
            map_chr(params, URLencode, reserved = TRUE),
            sep = "=",
            collapse = "&"
          )
        )
        updateQueryString(query, mode = "replace")
      })

      # Controls ----

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
        sel_key <- \(type) {
          if (!is.null(sel) && sel$type == type) sel$key else ""
        }

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

        sel_line <- function(map, g) {
          map |>
            add_line_layer(
              id = paste0(g, "-sel"),
              source = paste0(g, "-fill"),
              line_color = brand$red,
              line_width = 3,
              filter = list("==", get_column("key"), sel_key(g))
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
          add_circle_layer(
            id = "site-sel",
            source = select(app_sites, site_key),
            circle_radius = 11,
            circle_color = "rgba(0,0,0,0)",
            circle_stroke_color = brand$red,
            circle_stroke_width = 3,
            filter = list("==", get_column("site_key"), sel_key("site"))
          ) |>
          add_navigation_control(show_compass = FALSE) |>
          add_fullscreen_control() |>
          add_map_legends(f, geo, metric)
      })

      ## legends ----
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
              unique_id = "legend-area"
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
            unique_id = "legend-sites"
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
        key_for <- \(type) {
          if (!is.null(sel) && sel$type == type) sel$key else ""
        }
        proxy |>
          set_filter(
            "county-sel",
            list("==", get_column("key"), key_for("county"))
          ) |>
          set_filter(
            "wshed-sel",
            list("==", get_column("key"), key_for("wshed"))
          ) |>
          set_filter(
            "site-sel",
            list("==", get_column("site_key"), key_for("site"))
          )
      })

      ## map clicks ----
      observeEvent(input$map_feature_click, {
        f <- input$map_feature_click
        props <- f$properties
        new_sel <- switch(
          f$layer,
          "county-fill" = ,
          "county-hatch" = list(type = "county", key = props$key),
          "wshed-fill" = ,
          "wshed-hatch" = list(type = "wshed", key = props$key),
          "sites" = list(type = "site", key = props$site_key),
          NULL # basemap features are ignored
        )
        req(new_sel)
        # clicking the active selection again clears it
        if (identical(new_sel, rv$sel)) rv$sel <- NULL else rv$sel <- new_sel
      })

      ## table row clicks ----
      observeEvent(input$site_row, {
        key <- input$site_row
        rv$sel <- list(type = "site", key = key)
        site <- filter(app_sites, site_key == key)
        proxy |>
          fly_to(center = c(site$map_lon, site$map_lat), zoom = 10)
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
            h5(class = "mb-0", sel_name()),
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
        stat <- function(value, label, sub = NULL) {
          div(
            class = "stat",
            div(class = "stat-value", value),
            div(class = "stat-label", label),
            if (!is.null(sub)) div(class = "stat-sub", sub)
          )
        }
        div(
          class = "stat-row",
          stat(
            fmt_n(s$n_samples),
            "samples",
            paste(fmt_n(s$n_sites), if (s$n_sites == 1) "site" else "sites")
          ),
          stat(
            fmt_pct(s$det_freq, 0),
            "detected",
            paste(fmt_n(s$n_detected), "samples")
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
            }
          ),
          stat(
            fmt_pct(e$n_exceed / e$n, 0),
            "exceed benchmark",
            if (e$n_indet > 0) paste(fmt_n(e$n_indet), "indeterminate")
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
        plot_annual(d)
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
    }
  )
}
