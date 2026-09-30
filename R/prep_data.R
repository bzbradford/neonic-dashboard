## DATA PREP ##

# Reads raw DATCP neonicotinoid monitoring data and boundary layers, cleans and
# harmonizes them, and saves everything the analysis and app need to
# app/data.RData. Run from the project root:
#   source("R/prep_data.R")
# Data decisions referenced below (D1, D2, ...) are documented in PLAN.md.

library(tidyverse)
library(janitor)
library(sf)

rm(list = ls())


# Settings ---------------------------------------------------------------------

# D3: analytes selectable in the app; others are reported as screened only
featured_analytes <- c("Imidacloprid", "Clothianidin", "Thiamethoxam")

site_types <- c("Surface water", "Groundwater")

# projected CRS for spatial joins and distances (Wisconsin Transverse Mercator)
crs_wtm <- 3071

# D12: private well display location
blur_grid_deg <- 0.01 # snap grid (~1.1 km N-S, ~0.8 km E-W)
blur_inset_m <- 50 # min distance inside the correct county/watershed zone

epa_benchmark_url <- "https://www.epa.gov/pesticide-science-and-assessing-pesticide-risks/aquatic-life-benchmarks-and-ecological-risk"
nr140_url <- "https://dnr.wisconsin.gov/topic/Groundwater/NR140.html"

data_dir <- function(f) file.path("data", f)
shp_dir <- function(f) file.path("shp", f)

stopifnot(
  "Run from the project root" = file.exists(data_dir(
    "neonic_data_groundwater.csv"
  ))
)


# Boundaries -------------------------------------------------------------------

counties <- read_sf(shp_dir("wi-county-bounds-24k.fgb")) |>
  select(
    county = county_name,
    county_fips = county_fips_code,
    dnr_region = dnr_region_name
  ) |>
  arrange(county)

watersheds <- read_sf(shp_dir("wi-dnr-watersheds.fgb")) |>
  clean_names() |>
  select(
    wshed_code,
    wshed_name,
    wshed_sq_mi = watershed_size_sq_miles_amt
  ) |>
  arrange(wshed_code)

wi_state <- counties |>
  st_union() |>
  st_as_sf() |>
  rename(geometry = x)

counties_wtm <- st_transform(counties, crs_wtm)
watersheds_wtm <- st_transform(watersheds, crs_wtm)


# Raw data ---------------------------------------------------------------------

gw_raw <- read_csv(
  data_dir("neonic_data_groundwater.csv"),
  col_types = cols(
    WUWN = "c",
    WellUse = "c",
    SampleDate = col_date(),
    Analyte = "c",
    Units = "c",
    .default = "d"
  )
) |>
  clean_names()

sw_raw <- read_csv(
  data_dir("neonic_data_surfacewater.csv"),
  col_types = cols(
    StationID = "c",
    StationName = "c",
    SampleDate = col_date(),
    Analyte = "c",
    Units = "c",
    .default = "d"
  )
) |>
  clean_names()

thresholds_raw <- read_csv(
  data_dir("neonic_thresholds.csv"),
  col_types = cols(analyte = "c", .default = "d")
)

stopifnot(
  "Unexpected units" = all(c(gw_raw$units, sw_raw$units) == "µg/L"),
  "Missing results" = !anyNA(c(gw_raw$result, sw_raw$result)),
  "Missing detection limits" = !anyNA(c(
    gw_raw$detection_limit,
    sw_raw$detection_limit
  )),
  "Missing coordinates" = !anyNA(c(
    gw_raw$latitude,
    gw_raw$longitude,
    sw_raw$latitude,
    sw_raw$longitude
  ))
)


# Sites ------------------------------------------------------------------------

## Raw site lists ----

gw_sites_raw <- gw_raw |>
  distinct(
    wuwn,
    lat = latitude,
    lon = longitude,
    well_use,
    well_depth,
    casing_depth,
    bedrock_depth,
    static_water_depth
  )

sw_sites_raw <- sw_raw |>
  distinct(
    station_id,
    station_name,
    lat = latitude,
    lon = longitude
  )

stopifnot(
  "Wells with conflicting metadata" = !anyDuplicated(gw_sites_raw$wuwn),
  "Stations with conflicting metadata" = !anyDuplicated(sw_sites_raw$station_id)
)

## D13: anonymous IDs for private wells ----

private_well_ids <- gw_sites_raw |>
  filter(str_detect(well_use, "^Private")) |>
  select(wuwn) |>
  arrange(wuwn)

set.seed(140)
private_well_ids <- private_well_ids |>
  mutate(site_id = sprintf("PW-%04d", sample(n())))

# crosswalk stays in data/ (gitignored) and out of the app data
write_csv(private_well_ids, data_dir("private_well_ids.csv"))

## Harmonize ----

gw_sites <- gw_sites_raw |>
  left_join(private_well_ids, join_by(wuwn)) |>
  mutate(
    private_well = !is.na(site_id),
    site_id = coalesce(site_id, wuwn),
    site_type = "Groundwater",
    site_name = if_else(private_well, well_use, paste(well_use, wuwn))
  )

sw_sites <- sw_sites_raw |>
  mutate(
    site_id = station_id,
    site_type = "Surface water",
    site_name = station_name,
    private_well = FALSE
  )

sites <- bind_rows(sw_sites, gw_sites) |>
  select(
    site_type,
    site_id,
    site_name,
    lat,
    lon,
    private_well,
    well_use,
    well_depth,
    casing_depth,
    bedrock_depth,
    static_water_depth,
    wuwn
  )

## Spatial joins on true coordinates ----

# joins points to the polygon they fall in, or the nearest polygon if outside
join_nearest <- function(pts, polys, cols) {
  joined <- st_join(pts, polys[cols], join = st_intersects, left = TRUE)
  stopifnot("Point falls in overlapping polygons" = nrow(joined) == nrow(pts))
  missing <- is.na(joined[[cols[1]]])
  if (any(missing)) {
    nearest <- st_nearest_feature(pts[missing, ], polys)
    for (col in cols) {
      joined[[col]][missing] <- polys[[col]][nearest]
    }
  }
  joined$outside_wi <- missing
  joined
}

sites_wtm <- sites |>
  st_as_sf(coords = c("lon", "lat"), crs = 4326, remove = FALSE) |>
  st_transform(crs_wtm) |>
  join_nearest(counties_wtm, c("county", "county_fips", "dnr_region")) |>
  rename(outside_county = outside_wi) |>
  join_nearest(watersheds_wtm, c("wshed_code", "wshed_name")) |>
  rename(outside_wshed = outside_wi)

## D12: blur private well locations ----

# snap points to a lat/lng grid, then move any snapped point that changed
# county or watershed (in any of `layer_sets`) to the nearest point at least
# `inset` m inside its true county/watershed zone
blur_points <- function(pts_wtm, layer_sets, grid, inset) {
  snapped <- pts_wtm |>
    st_transform(4326) |>
    st_coordinates() |>
    (\(xy) round(xy / grid) * grid)() |>
    as_tibble() |>
    st_as_sf(coords = c("X", "Y"), crs = 4326) |>
    st_transform(crs_wtm) |>
    st_geometry()

  first_hit <- function(sgbp) {
    vapply(sgbp, \(x) if (length(x) > 0) x[1] else NA_integer_, integer(1))
  }

  # must match the true county and watershed in every layer version
  check_zone <- function(geom) {
    layer_sets |>
      map(function(lyr) {
        cnty <- lyr$counties$county[first_hit(st_intersects(
          geom,
          lyr$counties
        ))]
        wshed <- lyr$watersheds$wshed_code[first_hit(st_intersects(
          geom,
          lyr$watersheds
        ))]
        coalesce(cnty == pts_wtm$county & wshed == pts_wtm$wshed_code, FALSE)
      }) |>
      reduce(`&`)
  }

  ok <- check_zone(snapped)
  n_moved <- sum(!ok)

  if (n_moved > 0) {
    fix_idx <- which(!ok)
    zones <- pts_wtm[fix_idx, ] |>
      st_drop_geometry() |>
      distinct(county, wshed_code)
    zone_geoms <- zones |>
      pmap(function(county, wshed_code) {
        zone <- layer_sets |>
          map(\(lyr) {
            list(
              st_geometry(lyr$counties[lyr$counties$county == county, ]),
              st_geometry(lyr$watersheds[
                lyr$watersheds$wshed_code == wshed_code,
              ])
            )
          }) |>
          list_flatten() |>
          reduce(st_intersection) |>
          st_union()
        stopifnot("Empty county/watershed zone" = !st_is_empty(zone))
        inner <- st_buffer(zone, -inset)
        if (st_is_empty(inner)) zone else inner
      })
    zone_key <- paste(zones$county, zones$wshed_code)

    for (i in fix_idx) {
      zone <- zone_geoms[[match(
        paste(pts_wtm$county[i], pts_wtm$wshed_code[i]),
        zone_key
      )]]
      snapped[i] <- st_nearest_points(snapped[i], zone) |>
        st_cast("POINT") |>
        (\(p) p[2])()
    }
    ok <- check_zone(snapped)
  }

  stopifnot("Blurred points outside true county/watershed" = all(ok))

  list(
    geometry = snapped,
    n_moved = n_moved,
    offset_m = as.numeric(st_distance(snapped, st_geometry(pts_wtm), by_element = TRUE))
  )
}

# blurred points are checked against both the full-resolution layers used for
# the joins and the simplified layers drawn on maps
counties_map <- counties |>
  rmapshaper::ms_simplify(keep = 0.05, keep_shapes = TRUE)

watersheds_map <- watersheds |>
  rmapshaper::ms_simplify(keep = 0.03, keep_shapes = TRUE)

layer_sets <- list(
  full = list(counties = counties_wtm, watersheds = watersheds_wtm),
  map = list(
    counties = st_transform(counties_map, crs_wtm),
    watersheds = st_transform(watersheds_map, crs_wtm)
  )
)

private_idx <- which(sites_wtm$private_well)
blurred <- blur_points(
  sites_wtm[private_idx, ],
  layer_sets,
  blur_grid_deg,
  blur_inset_m
)
blurred_ll <- blurred$geometry |>
  st_transform(4326) |>
  st_coordinates()

sites <- sites_wtm |>
  st_drop_geometry() |>
  mutate(map_lat = lat, map_lon = lon, location_blurred = FALSE)
sites$map_lat[private_idx] <- blurred_ll[, "Y"]
sites$map_lon[private_idx] <- blurred_ll[, "X"]
sites$location_blurred[private_idx] <- TRUE


# Results ----------------------------------------------------------------------

## Harmonize ----

results_raw <- bind_rows(
  gw_raw |>
    left_join(select(gw_sites, wuwn, site_id), join_by(wuwn)) |>
    mutate(site_type = "Groundwater"),
  sw_raw |>
    mutate(site_type = "Surface water", site_id = station_id)
) |>
  select(
    site_type,
    site_id,
    date = sample_date,
    analyte,
    result,
    dl = detection_limit
  )

## D2: duplicates ----

n_exact_dups <- sum(duplicated(results_raw))

results <- results_raw |>
  distinct() |>
  # repeat samples on the same day (file order determines sequence)
  mutate(sample_seq = row_number(), .by = c(site_type, site_id, date, analyte))

## D1: detections ----

results <- results |>
  mutate(
    site_type = factor(site_type, site_types),
    analyte = str_to_title(analyte),
    year = year(date),
    month = month(date),
    detected = result > 0,
    estimated = detected & result < dl, # reported below the detection limit
    result = if_else(detected, result, NA_real_),
    featured = analyte %in% featured_analytes
  ) |>
  select(
    site_type,
    site_id,
    date,
    year,
    month,
    sample_seq,
    analyte,
    featured,
    detected,
    estimated,
    result,
    dl
  ) |>
  arrange(site_type, site_id, date, sample_seq, analyte)

all_analytes <- results |>
  summarize(detects = sum(detected), .by = analyte) |>
  arrange(desc(detects)) |>
  pull(analyte)

results <- results |>
  mutate(analyte = factor(analyte, all_analytes))


# Samples ----------------------------------------------------------------------

# one row per sampling event (site x date x seq)
# D4: total = sum of detected concentrations across all analytes, NDs as 0
samples <- results |>
  summarize(
    n_analytes = n(),
    n_detected = sum(detected),
    any_detected = any(detected),
    total_conc = sum(result, na.rm = TRUE),
    analytes_tested = paste(sort(as.character(analyte)), collapse = ", "),
    analytes_detected = paste(
      sort(as.character(analyte[detected])),
      collapse = ", "
    ),
    .by = c(site_type, site_id, date, year, month, sample_seq)
  ) |>
  mutate(total_conc = if_else(any_detected, total_conc, NA_real_))


# Benchmarks -------------------------------------------------------------------

benchmark_defs <- tribble(
  ~benchmark        , ~col                       , ~label                                                 , ~short_label      , ~primary_for    , ~source                                                                         , ~url              ,
  "aquatic_acute"   , "aquatic_acute_ppb"        , "EPA aquatic life benchmark, acute (invertebrates)"    , "Aquatic acute"   , "Surface water" , "US EPA Office of Pesticide Programs, Aquatic Life Benchmarks"                     , epa_benchmark_url ,
  "aquatic_chronic" , "aquatic_chronic_ppb"      , "EPA aquatic life benchmark, chronic (invertebrates)"  , "Aquatic chronic" , "Surface water" , "US EPA Office of Pesticide Programs, Aquatic Life Benchmarks"                     , epa_benchmark_url ,
  "proposed_es"     , "proposed_enforcement_ppb" , "Proposed WI groundwater enforcement standard (ES)"    , "Proposed ES"     , "Groundwater"   , "Wisconsin DNR, NR 140 groundwater quality standards, Cycle 13 review (proposed)" , nr140_url         ,
  "proposed_pal"    , "proposed_preventive_ppb"  , "Proposed WI groundwater preventive action limit (PAL)" , "Proposed PAL"    , "Groundwater"   , "Wisconsin DNR, NR 140 groundwater quality standards, Cycle 13 review (proposed)" , nr140_url         ,
) |>
  mutate(benchmark = fct_inorder(benchmark))

# long format: one row per analyte x benchmark, values in µg/L (= ppb)
benchmarks <- thresholds_raw |>
  mutate(analyte = str_to_title(analyte)) |>
  pivot_longer(-analyte, names_to = "col", values_to = "value") |>
  drop_na(value) |>
  left_join(benchmark_defs, join_by(col)) |>
  select(-col) |>
  mutate(analyte = factor(analyte, all_analytes)) |>
  arrange(analyte, benchmark)

stopifnot(
  "Unknown threshold column" = !anyNA(benchmarks$benchmark),
  "Unknown threshold analyte" = !anyNA(benchmarks$analyte)
)


# Exceedances ------------------------------------------------------------------

# D7: one row per result x applicable benchmark
#   Exceeds       = detected at or above the benchmark
#   Below         = detected below it, or ND with a detection limit at or below it
#   Indeterminate = ND, but the detection limit is above the benchmark
exceedances <- results |>
  inner_join(
    select(benchmarks, analyte, benchmark, value),
    join_by(analyte),
    relationship = "many-to-many"
  ) |>
  mutate(
    status = case_when(
      detected & result >= value ~ "Exceeds",
      detected ~ "Below",
      dl <= value ~ "Below",
      .default = "Indeterminate"
    ) |>
      factor(c("Exceeds", "Below", "Indeterminate"))
  ) |>
  select(
    site_type,
    site_id,
    date,
    year,
    sample_seq,
    analyte,
    benchmark,
    value,
    result,
    dl,
    status
  )


# Site summaries ---------------------------------------------------------------

## Per site x analyte (the "analyte screen" for popups) ----

site_analytes <- results |>
  summarize(
    n_samples = n(),
    n_detected = sum(detected),
    max_result = if (any(detected)) max(result, na.rm = TRUE) else NA_real_,
    first_date = min(date),
    last_date = max(date),
    .by = c(site_type, site_id, analyte)
  ) |>
  arrange(site_type, site_id, analyte)

## Per site ----

site_summary <- samples |>
  summarize(
    n_samples = n(),
    n_detected = sum(any_detected),
    first_date = min(date),
    last_date = max(date),
    n_years = n_distinct(year),
    max_total_conc = if (any(any_detected)) {
      max(total_conc, na.rm = TRUE)
    } else {
      NA_real_
    },
    .by = c(site_type, site_id)
  )

site_exceedances <- exceedances |>
  summarize(
    n_exceed = sum(status == "Exceeds"),
    .by = c(site_type, site_id, benchmark)
  ) |>
  pivot_wider(
    names_from = benchmark,
    values_from = n_exceed,
    names_prefix = "n_exceed_",
    values_fill = 0
  )

sites <- sites |>
  mutate(site_type = factor(site_type, site_types)) |>
  left_join(site_summary, join_by(site_type, site_id)) |>
  left_join(site_exceedances, join_by(site_type, site_id)) |>
  mutate(
    site_label = case_when(
      site_type == "Surface water" ~ sprintf("%s (%s)", site_name, site_id),
      private_well ~ sprintf("Private well %s (%s Co.)", site_id, county),
      .default = site_name
    ),
    .after = site_name
  ) |>
  arrange(site_type, site_id)

stopifnot(
  "Sites without samples" = !anyNA(sites$n_samples),
  "Results without sites" = all(
    paste(results$site_type, results$site_id) %in%
      paste(sites$site_type, sites$site_id)
  )
)


# Validation summary -----------------------------------------------------------

validation <- list(
  raw_rows = c(groundwater = nrow(gw_raw), surface = nrow(sw_raw)),
  exact_duplicates_removed = n_exact_dups,
  repeat_same_day_samples = results |>
    filter(sample_seq > 1) |>
    distinct(site_type, site_id, date),
  estimated_below_dl = results |>
    filter(estimated) |>
    select(site_type, site_id, date, analyte, result, dl),
  dl_by_year = results |>
    count(site_type, year, dl) |>
    arrange(site_type, year, dl),
  sites_outside_wi = sites |>
    filter(outside_county | outside_wshed) |>
    select(site_type, site_id, site_label, county, wshed_name),
  blur = list(
    n_private_wells = length(private_idx),
    n_moved_to_zone = blurred$n_moved,
    offset_m = summary(blurred$offset_m),
    n_shared_locations = sites |>
      filter(location_blurred) |>
      count(map_lat, map_lon) |>
      filter(n > 1) |>
      nrow()
  )
)

message("== Validation ==")
message("Exact duplicate rows removed: ", validation$exact_duplicates_removed)
message(
  "Same-day repeat samples: ",
  nrow(validation$repeat_same_day_samples)
)
message("Results below DL (estimated): ", nrow(validation$estimated_below_dl))
message("Sites outside WI polygons: ", nrow(validation$sites_outside_wi))
message(
  sprintf(
    "Private wells blurred: %d (%d moved into true zone); offset median %.0f m, max %.0f m",
    validation$blur$n_private_wells,
    validation$blur$n_moved_to_zone,
    median(blurred$offset_m),
    max(blurred$offset_m)
  )
)


# Save -------------------------------------------------------------------------

# map layers: counties_map and watersheds_map were simplified before blurring
wi_state_map <- counties_map |>
  st_union() |>
  st_as_sf() |>
  rename(geometry = x)

# true coordinates and WUWNs of private wells are removed before saving
sites <- sites |>
  mutate(
    lat = if_else(private_well, NA_real_, lat),
    lon = if_else(private_well, NA_real_, lon),
    wuwn = if_else(private_well, NA_character_, wuwn)
  )

counties <- counties_map
watersheds <- watersheds_map
wi_state <- wi_state_map

dir.create("app", showWarnings = FALSE)

save(
  featured_analytes,
  all_analytes,
  site_types,
  sites,
  results,
  samples,
  benchmarks,
  exceedances,
  site_analytes,
  validation,
  counties,
  watersheds,
  wi_state,
  file = "app/data.RData"
)

message("Saved app/data.RData (", format(file.size("app/data.RData") / 1e6, digits = 2), " MB)")
