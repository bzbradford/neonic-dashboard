library(tidyverse)
library(sf)

# boundaries
wi_counties <- read_sf("shp/wi-county-bounds-24k.fgb")
wi_state <- st_union(wi_counties)

ggplot() +
  geom_sf(data = wi_state, fill = "white", color = NA) +
  theme_void() +
  theme(plot.background = element_rect(fill = "#c5050c", color = NA))

ggsave(
  "dev/icon/wi_state.png",
  width = 512,
  height = 512,
  units = "px",
  dpi = 300
)
