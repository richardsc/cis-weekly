
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

rasterize <- function(x, dest, var, scale = 1, select = NULL, where = NULL,
                      nodata = 255, type = "Byte") {
  region <- str_extract(x, "[A-Z]{2}")
  date <- str_extract(x, "[0-9-]{10}")

  # Using the advanced version (gdal_utils instead of stars::st_rasterize)
  # because gdal_utils allows setting output type/compression and is faster.
  # Optimizing for speed over readability here in a big way.
  # https://gdal.org/programs/gdal_rasterize.html
  if (is.null(where)) {
    where <- glue::glue("{ var } IS NOT NULL")
  }

  select <- c(select, glue::glue("{ var } * { scale } as rasterize_col"), "geom")
  select <- glue::glue_collapse(select, sep = ", ")

  gdal_utils(
    "rasterize",
    x,
    dest,
    options = c(
      "-sql",
      glue::glue(
        "SELECT { select } FROM `{ region }_{ date }` WHERE { where }"
      ),
      "-a", "rasterize_col",
      "-init", nodata,
      "-a_nodata", nodata,
      "-te", unname(bboxes[[region]][c("xmin", "ymin", "xmax", "ymax")]),
      "-tr", cell_size, cell_size,
      "-ot", type,
      "-co", "COMPRESS=LZW"
    )
  )
}

# parellellizing here makes a huge difference and works well because
# there is a 1--1 relationship between input file and output file
future::plan(future::multisession, workers = future::availableCores() - 1)

# all N_* columns
n_cols <- c(
  "N_CT", "N_COI", "N_CMY", "N_CSY", "N_CFY", "N_CFY_TK", "N_CFY_M",
  "N_CFY_TN", "N_CYI", "N_CGW", "N_CG", "N_CN", "N_CB", "N_CVTK",
  "N_CTK", "N_CM", "N_CTN"
)

for (col in n_cols) {
  message(glue::glue("Processing column '{ col }'"))

  suffix <- col %>% str_to_lower() %>% str_replace("_", "-")
  dir <- file.path("tif", suffix)
  if (!dir.exists(dir)) dir.create(dir)

  gpkg_meta %>%
    transmute(
      x = gpkg_standardized,
      dest = glue::glue("{ dir }/{ region }_{ date }_{ suffix }.tif")
    ) %>%
    filter(!file.exists(dest)) %>%
    furrr::future_pwalk(
      ., rasterize,
      var = col,
      scale = 10,
      type = "Byte",
      nodata = 255,
      .progress = TRUE
    )
}

# PNT_TYPE column

if (!dir.exists("tif/pnt-type")) dir.create("tif/pnt-type")

gpkg_meta %>%
  transmute(
    x = gpkg_standardized,
    dest = glue::glue("tif/pnt-type/{ region }_{ date }_pnt-type.tif")
  ) %>%
  filter(!file.exists(dest)) %>%
  furrr::future_pwalk(
    ., rasterize,
    var = "PNT_TYPE",
    type = "Int16",
    nodata = -9999,
    .progress = TRUE
  )

# E_ columns (WIP)

