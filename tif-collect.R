
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
  region <- str_extract(basename(x), "[A-Z]{2}")
  date <- str_extract(basename(x), "[0-9-]{10}")

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

  suffix <- col %>% str_to_lower() %>% str_replace_all("_", "-")
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

# E_ columns (require string -> integer mapping)
# read from yaml and write to csv

coding_yaml <- yaml::read_yaml("raster-codes.yaml")

variables <- tibble(
  category = map_chr(coding_yaml, "category"),
  variables = map(coding_yaml, "variables")
) %>%
  unnest_longer(variables) %>%
  unnest_wider(variables) %>%
  write_csv("tif/variables.csv")

value_mapping <- tibble(
  category = map_chr(coding_yaml, "category"),
  coding = map(coding_yaml, "coding")
) %>%
  unnest_longer(coding) %>%
  unnest_wider(coding) %>%
  write_csv("tif/value_mapping.csv")


e_cols <- c(
  "E_CT", "E_CA", "E_CB", "E_CC", "E_CD", "E_SO", "E_SA", "E_SB",
  "E_SC", "E_SD", "E_SE", "E_FA", "E_FB", "E_FC", "E_FD", "E_FE"
)

if (any(!(e_cols %in% variables$column))) {
  stop("Some `e_cols` do not have a mapping defined in `variables`")
}

mappings <- variables %>%
  select(category, column) %>%
  left_join(value_mapping, by = "category") %>%
  select(column, column_value, raster_value) %>%
  group_by(column) %>%
  nest(data = c(column_value, raster_value)) %>%
  deframe() %>%
  map(deframe)

rasterize_codified_cols <- function(gpkg, region, date) {
  suffix <- e_cols %>% str_to_lower() %>% str_replace_all("_", "-")
  dir <- file.path("tif", suffix)
  dest <- glue::glue("{ dir }/{ region }_{ date }_{ suffix }.tif")
  if (all(file.exists(dest))) {
    return()
  }

  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  tmp_gpkg <- file.path(tmp_dir, basename(gpkg))
  on.exit(unlink(tmp_dir, recursive = TRUE))

  df <- read_sf(gpkg) %>% select(all_of(e_cols)) %>% as_tibble()
  df[e_cols] <- map(df[e_cols], na_if, "")
  df[e_cols] <- map2(df[e_cols], mappings[e_cols], ~unname(.y[.x]))
  write_sf(df, tmp_gpkg)

  for (i in seq_along(e_cols)) {
    if (file.exists(dest[i])) {
      break
    }
    if (!dir.exists(dir[i])) dir.create(dir[i])
    rasterize(
      tmp_gpkg, dest[i],
      var = e_cols[i],
      type = "Byte",
      nodata = 255
    )
  }
}

# process all files
gpkg_meta %>%
  select(gpkg = gpkg_standardized, region, date) %>%
  furrr::future_pwalk(rasterize_codified_cols, ..progress = TRUE)
