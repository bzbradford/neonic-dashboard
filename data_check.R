library(tidyverse)
library(sf)
library(leaflet)

# boundaries
wi_counties <- read_sf("shp/wi-counties.fgb")
wi_state <- st_union(wi_counties)

# load and view watershed layers
watersheds <- list(
  dnr = read_sf("shp/wi-dnr-watersheds.fgb"),
  huc8 = read_sf("shp/wi-huc-8-subbasins.fgb"),
  huc10 = read_sf("shp/wi-huc-10-watersheds.fgb"),
  huc12 = read_sf("shp/wi-huc-12-subwatersheds.fgb")
)

leaflet() |>
  addProviderTiles(providers$Esri.WorldTopoMap) |>
  addPolygons(
    data = watersheds$dnr,
    color = "blue",
    weight = 1,
    fillOpacity = 0.2,
    group = "DNR Watersheds"
  ) |>
  addPolygons(
    data = watersheds$huc8,
    color = "green",
    weight = 1,
    fillOpacity = 0.2,
    group = "HUC-8 Subbasins"
  ) |>
  addPolygons(
    data = watersheds$huc10,
    color = "orange",
    weight = 1,
    fillOpacity = 0.2,
    group = "HUC-10 Watersheds"
  ) |>
  addPolygons(
    data = watersheds$huc12,
    color = "red",
    weight = 1,
    fillOpacity = 0.2,
    group = "HUC-12 Subwatersheds"
  ) |>
  addLayersControl(
    overlayGroups = c(
      "DNR Watersheds",
      "HUC-8 Subbasins",
      "HUC-10 Watersheds",
      "HUC-12 Subwatersheds"
    ),
    options = layersControlOptions(collapsed = FALSE)
  )

# load neonics ----

neonics_gw <- read_csv("data/neonic_data_groundwater.csv") |>
  janitor::clean_names() |>
  mutate(
    detect = result >= detection_limit,
    log_result = if_else(detect, log10(result), NA_real_)
  )

# validate lat/lng
# range(neonics_gw$latitude)
# range(neonics_gw$longitude)

neonics_sw <- read_csv("data/neonic_data_surfacewater.csv") |>
  janitor::clean_names() |>
  mutate(
    detect = result >= detection_limit,
    log_result = if_else(detect, log10(result), NA_real_)
  )

# validate lat/lng
# range(neonics_sw$latitude)
# range(neonics_sw$longitude)

# create sf objects
neonics_gw_sf <- st_as_sf(
  neonics_gw,
  coords = c("longitude", "latitude"),
  crs = 4326
)

neonics_sw_sf <- st_as_sf(
  neonics_sw,
  coords = c("longitude", "latitude"),
  crs = 4326
)

leaflet() |>
  addProviderTiles(providers$Esri.WorldTopoMap) |>
  addPolygons(
    data = watersheds$dnr,
    color = "blue",
    weight = 1,
    fillOpacity = 0.2,
    group = "DNR Watersheds"
  ) |>
  addCircleMarkers(
    data = neonics_gw_sf,
    radius = 3,
    color = "purple",
    weight = 0.25,
    fillColor = ~ colorNumeric(
      palette = "viridis",
      domain = neonics_gw_sf$log_result
    )(neonics_gw_sf$log_result),
    fillOpacity = 0.5,
    group = "Groundwater Neonics"
  ) |>
  addCircleMarkers(
    data = neonics_sw_sf,
    radius = 3,
    color = "orange",
    weight = 0.25,
    fillColor = ~ colorNumeric(
      palette = "viridis",
      domain = neonics_sw_sf$log_result
    )(neonics_sw_sf$log_result),
    fillOpacity = 0.5,
    group = "Surface Water Neonics"
  )
