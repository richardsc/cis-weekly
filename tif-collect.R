
library(tidyverse)
library(sf)
library(stars)

zip_meta <- read_csv("zip/meta.csv", col_types = cols())
gpkg_meta <- read_csv("gpkg-standardized/meta.csv", col_types = cols()) %>%
  left_join(zip_meta, by = "gpkg")

# make grids so that they align on multiples of cell_size
# (may help align grids between regions later because overlapping
# cells will have the same extents)
cell_size <- 1000

grid_extents <- gpkg_meta %>%
  group_by(region) %>%
  summarise(
    xmin = floor(min(gpkg_xmin) / cell_size) * cell_size,
    ymin = floor(min(gpkg_ymin) / cell_size) * cell_size,
    xmax = ceiling(max(gpkg_xmax) / cell_size) * cell_size,
    ymax = ceiling(max(gpkg_ymax) / cell_size) * cell_size,
    bbox = list(
      st_bbox(
        c(xmin = xmin, ymin = ymin, xmax = xmax, ymax = ymax),
        crs = st_crs(read_sf(gpkg_meta$gpkg_standardized[1]))
      )
    )
  )

if (!dir.exists("tif")) dir.create("tif")

# create raster template grids along which all files from that
# region should be aligned
bboxes <- set_names(grid_extents$bbox, grid_extents$region)
templates <- map(bboxes, st_as_stars, values = 1L, dx = cell_size, dy = cell_size, inside = TRUE)
template_files <- set_names(glue::glue("tif/{ names(templates) }-template.tif"), names(templates))

# write template grids to disk
walk2(
  templates,
  template_files,
  write_stars,
  type = "Byte",
  options = "COMPRESS=LZW"
)

rasterize_n_ct <- function(x, dest, pb) {
  pb$tick()

  region <- str_extract(x, "[A-Z]{2}")
  date <- str_extract(x, "[0-9-]{10}")

  # Using the advanced version (gdal_utils instead of stars::st_rasterize)
  # because gdal_utils allows setting output type/compression and is faster.
  # Optimizing for speed over readability here in a big way.
  # https://gdal.org/programs/gdal_rasterize.html
  gdal_utils(
    "rasterize",
    x,
    dest,
    options = c(
      "-sql",
      glue::glue(
        "SELECT PNT_TYPE, N_CT * 10 as rasterize_col, geom FROM `{ region }_{ date }` WHERE PNT_TYPE < 400"
      ),
      "-a", "rasterize_col",
      "-init", "255",
      "-a_nodata", "255",
      "-te", unname(bboxes[[region]][c("xmin", "ymin", "xmax", "ymax")]),
      "-tr", cell_size, cell_size,
      "-ot", "Byte",
      "-co", "COMPRESS=LZW"
    )
  )
}

if (!dir.exists("tif/n-ct")) dir.create("tif/n-ct")

gpkg_meta %>%
  transmute(
    x = gpkg_standardized,
    dest = glue::glue("tif/n-ct/{ region }_{ date }_n-ct.tif")
  ) %>%
  filter(!file.exists(dest)) %>%
  pwalk(., rasterize_n_ct, pb = progress::progress_bar$new(total = nrow(.)))

