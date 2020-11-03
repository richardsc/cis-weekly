
library(tidyverse)
library(arrow)
library(vapour)

gpkg_files <- list.files("gpkg", "\\.gpkg$", full.names = TRUE)

read_gpkg_tbl <- function(x, pb = progress::progress_bar$new(total = 1e6)) {
  pb$tick()
  # faster than read_sf() because it summarizes geometry
  attr <- vapour::vapour_read_attributes(x)
  geom_sum <- vapour::vapour_geom_summary(x)

  tibble(
    region = str_extract(x, "[A-Z]{2}"),
    date = as.Date(str_extract(x, "[0-9-]+")),
    feat_id = geom_sum$FID,
    feat_xmin = geom_sum$xmin,
    feat_ymin = geom_sum$ymin,
    feat_xmax = geom_sum$xmax,
    feat_ymax = geom_sum$ymax,
    !!! attr
  )
}

tbls <- gpkg_files %>%
  map(., read_gpkg_tbl, pb = progress::progress_bar$new(total = length(.)))

# write all attributes as a parquet file (can be lazily loaded/filtered
# by the arrow package)
attrs <- vctrs::vec_rbind(!!! tbls) %>%
  mutate_at(vars(starts_with("N_")), na_if, "") %>%
  mutate_at(vars(starts_with("N_")), as.numeric) %>%
  select(-starts_with("R_")) %>%
  write_parquet("attrs.parquet", compression = "snappy")
