
library(tidyverse)
library(arrow)
library(vapour)

gpkg_files <- list.files("gpkg", "\\.gpkg$", full.names = TRUE)

read_gpkg_tbl <- function(x, pb) {
  pb$tick()
  # faster than read_sf() because it ignores geometry
  as_tibble(vapour_read_attributes(x))
}

read_gpkg_extent <- function(x, pb) {
  pb$tick()
  # faster than read_sf() because it ignores geometry
  list_of_bbox <- vapour_read_extent(x)
  tibble(
    # each element is c(xmin, xmax, ymin, ymax)
    feat_xmin = map_dbl(list_of_bbox, `[[`, 1),
    feat_ymin = map_dbl(list_of_bbox, `[[`, 3),
    feat_xmax = map_dbl(list_of_bbox, `[[`, 2),
    feat_ymax = map_dbl(list_of_bbox, `[[`, 4)
  )
}

extent <- gpkg_files %>%
  set_names() %>%
  map(., read_gpkg_extent, pb = progress::progress_bar$new(total = length(.)))

tbls <- gpkg_files %>%
  set_names() %>%
  map(., read_gpkg_tbl, pb = progress::progress_bar$new(total = length(.))) %>%
  map2(extent, vctrs::vec_cbind)

# this is a grouped mutate, but grouping is slow
# and unnecessary because everything is already grouped
tbls_to_write <- tbls %>%
  imap(~{
    mutate(
      .x,
      region = str_extract(.y, "[A-Z]{2}"),
      date = as.Date(str_extract(.y, "[0-9-]+")),
      row_id = seq_len(n())
    )
  })

# write all attributes as a parquet file (can be lazily loaded/filtered
# by the arrow package)
attrs <- vctrs::vec_rbind(!!! tbls_to_write) %>%
  select(region, date, row_id, starts_with("feat_"), everything()) %>%
  write_parquet("attrs.parquet", compression = "snappy")
