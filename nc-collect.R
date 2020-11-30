
library(tidyverse)
library(stars)
library(ncdf4)

# generate the mapping information

e_value_mapping <- read_csv(
  "tif/value_mapping.csv",
  col_types = cols(
    category = col_character(),
    column_value = col_character(),
    raster_value = col_double(),
    quantitative_definition = col_character(),
    definition = col_character(),
    notes = col_character()
  )
) %>%
  mutate(column_value = str_replace(column_value, '"unknown"', "unknown")) %>%
  group_by(category) %>%
  summarise(
    mapping = glue::glue_collapse(
      glue::glue('{{"raster_value": "{ raster_value }", "column_value": "{ column_value }", "quantitative_definition": "{ quantitative_definition }", "definition": "{ definition }"}}'),
      sep = ", "
    ) %>%
      paste0("[", ., "]")
  )

# make sure mappings can be parsed as JSON
walk(e_value_mapping$mapping, jsonlite::fromJSON)

e_columns <- read_csv(
  "tif/variables.csv",
  col_types = cols(
    category = col_character(),
    column = col_character(),
    symbol = col_character(),
    definition = col_character(),
    notes = col_character()
  )
) %>%
  select(-notes) %>%
  left_join(e_value_mapping, by = "category") %>%
  mutate(long_name = glue::glue("{ symbol }: { definition }")) %>%
  select(-category, - symbol, -definition) %>%
  rename(units = mapping)

e_cols <- c(
  "E_CT", "E_CA", "E_CB", "E_CC", "E_CD", "E_SO", "E_SA", "E_SB",
  "E_SC", "E_SD", "E_SE", "E_FA", "E_FB", "E_FC", "E_FD", "E_FE"
)

n_columns <- tibble(
  column = c(
    "N_CT", "N_COI", "N_CMY", "N_CSY", "N_CFY", "N_CFY_TK", "N_CFY_M",
    "N_CFY_TN", "N_CYI", "N_CGW", "N_CG", "N_CN", "N_CB", "N_CVTK",
    "N_CTK", "N_CM", "N_CTN"
  ),
  long_name = column,
  units = "Original column value * 10"
)

columns <- bind_rows(e_columns, n_columns)

files <- columns %>%
  select(column) %>%
  mutate(
    file = column %>%
      str_to_lower() %>%
      str_replace_all("_", "-") %>%
      file.path("tif", .) %>%
      lapply(list.files, "\\.tif$", full.names = TRUE)
  ) %>%
  unnest(file) %>%
  mutate(
    region = str_sub(basename(file), 1, 2),
    date = as.Date(str_extract(basename(file), "[0-9-]{10}"))
  )

# used for land mask
pnt_type_tif_files <- list.files("tif/pnt-type", "\\.tif$", full.names = TRUE)

land_mask_region <- function(region, using_n_files = 100) {
  tif_region <- pnt_type_tif_files[str_starts(basename(pnt_type_tif_files), region)]

  tif0 <- read_stars(tif_region[1])
  tif0[[1]][] <- NA_integer_

  every_n_files <- length(tif_region) %/% using_n_files + 1

  for (i in seq_along(tif_region)) {
    # land definition is fairly stable, but does change over time
    # use subset of available files to calculate
    if (((i - 1) %% every_n_files) != 0) {
      next
    }

    tifi <- read_stars(tif_region[i])
    is_land <- tifi[[1]] >= 400
    tif0[[1]][!is.na(is_land) & is_land] <- 1L
    tif0[[1]][!is.na(is_land) & !is_land] <- 0L
  }

  tif0
}

region_to_netcdf <- function(region, pb = function(...) NULL) {
  pb(
    message = glue::glue("Preparing region '{ region }'"),
    class = "sticky",
    amount = 0
  )

  region_files <- files %>%
    filter(region == !! region) %>%
    select(-region)

  # make sure variables/regions exist on a perfect grid
  dates_region <- sort(unique(region_files$date))
  vars_region <- sort(unique(region_files$column))
  region_columns <- columns[match(vars_region, columns$column), ]

  region_files_grid <- crossing(
    tibble(column = vars_region),
    tibble(date = dates_region)
  ) %>%
    arrange(column, date) %>%
    left_join(region_files, by = c("column", "date"))

  tif0 <- read_stars(glue::glue("tif/{ region }-template.tif"))
  crs_chr <- st_crs(tif0)$Wkt

  # make empty tif that can be used as a fill if a date/variable combo
  # is not available
  tif_na <- tif0
  tif_na[[1]][] <- NA_integer_

  coords <- crossing(
    tibble(
      x = st_get_dimension_values(tif0, "x"),
      x_i = seq_along(x)
    ),
    tibble(
      y = st_get_dimension_values(tif0, "y"),
      y_i = seq_along(y)
    )
  ) %>%
    arrange(y_i, x_i)

  projected <- sf_project(
    to = st_crs(4326),
    from = st_crs(tif0),
    pts = coords[c("x", "y")]
  )
  coords[c("longitude", "latitude")] <- projected[, 1:2]

  # define NetCDF dimensions and variables
  dim_x <- ncdim_def("x", units = "meters", vals = st_get_dimension_values(tif0, "x"))
  dim_y <- ncdim_def("y", units = "meters", vals = st_get_dimension_values(tif0, "y"))
  dim_juld <- ncdim_def(
    "juld",
    units = "days since 1950-01-01",
    vals = as.integer(difftime(dates_region, as.Date("1950-01-01"), units = "days"))
  )

  # estimate land definition
  land_def <- land_mask_region(region)

  # This is a dummy variable whose attribute 'spatial_ref' carries the CRS.
  # Other variables must have an attribute 'grid_mapping' whose value is the
  # name of this variable.
  var_crs <- ncvar_def(
    "crs",
    units = "",
    dim = list(),
    prec = "integer"
  )

  var_land <- ncvar_def(
    "land",
    units = "boolean",
    dim = list(dim_x, dim_y),
    longname = "Land mask (1 for land, 0 for not land)",
    missval = 255L,
    prec = "integer",
    compression = 5
  )

  var_longitude <- ncvar_def(
    "longitude",
    units = "degrees",
    dim = list(dim_x, dim_y),
    longname = "Longitude (WGS84)",
    prec = "float",
    compression = 5
  )

  var_latitude <- ncvar_def(
    "latitude",
    units = "degrees",
    dim = list(dim_x, dim_y),
    longname = "Latitude (WGS84)",
    prec = "float",
    compression = 5
  )

  vars_value <- region_columns %>%
    rename(name = column, longname = long_name) %>%
    pmap(
      ncvar_def,
      dim = list(dim_x, dim_y, dim_juld),
      missval = 255L,
      prec = "integer",
      compression = 5
    )

  # create file
  nc <- nc_create(
    glue::glue("nc/{ region }.nc"),
    vars = c(
      list(var_crs, var_land, var_longitude, var_latitude),
      vars_value
    )
  )

  # always close even on error
  on.exit(nc_close(nc))

  # this is how GDAL writes CRS info
  ncatt_put(nc, var_crs, "spatial_ref", crs_chr)
  ncatt_put(nc, var_land, "grid_mapping", "crs")
  ncatt_put(nc, var_longitude, "grid_mapping", "crs")
  ncatt_put(nc, var_latitude, "grid_mapping", "crs")
  for (var in vars_value) {
    ncatt_put(nc, var, "grid_mapping", "crs")
  }

  # put constant variables for each region
  ncvar_put(nc, var_land, vals = land_def[[1]])
  ncvar_put(nc, var_longitude, vals = coords$longitude)
  ncvar_put(nc, var_latitude, vals = coords$latitude)

  pb(
    message = glue::glue("Prepared region '{ region }'"),
    class = "sticky",
    amount = 0
  )

  # write values one timestep at a time
  for (item in transpose(region_files_grid)) {
    if (is.na(item$file)) {
      strs <- tif_na
    } else {
      pb(message = item$file)
      strs <- read_stars(item$file)
    }

    vals <- strs[[1]]
    vals[is.na(vals)] <- 255L

    ncvar_put(
      nc,
      vars_value[[which(map_chr(vars_value, "name") == item$column)]],
      vals,
      start = c(1, 1, match(item$date, dates_region)),
      count = c(-1, -1, 1)
    )
  }
}

if (!dir.exists("nc")) dir.create("nc")


regions <- unique(str_extract(basename(files$file), "^[A-Z]{2}"))

# can only paralellize here using regions because packing
# each NetCDF file has to be done sequentially
future::plan(future::multisession, workers = future::availableCores() - 1)

progressr::handlers("progress")
progressr::with_progress({
  # initiate progressor! lets us specify one tick per file rather than
  # one tick by region
  pb <- progressr::progressor(steps = nrow(files))

  furrr::future_walk(
    regions,
    region_to_netcdf,
    pb = pb
  )
})
