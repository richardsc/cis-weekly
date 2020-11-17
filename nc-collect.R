
library(tidyverse)
library(stars)
library(ncdf4)

n_ct_tif_files <- list.files("tif/n-ct", "\\.tif$", full.names = TRUE)
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

region_to_netcdf <- function(region) {
  n_ct_tif_region <- n_ct_tif_files[str_starts(basename(n_ct_tif_files), region)]
  dates_region <- as.Date(str_extract(basename(n_ct_tif_region), "[0-9-]{10}"))

  tif0 <- read_stars(n_ct_tif_region[1])
  crs_chr <- st_crs(tif0)$Wkt

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

  var_n_ct <- ncvar_def(
    "n_ct",
    units = "percent",
    dim = list(dim_x, dim_y, dim_juld),
    longname = "Total ice concentration",
    missval = 255L,
    prec = "integer",
    compression = 5
  )

  # create file
  nc <- nc_create(
    glue::glue("nc/{ region }.nc"),
    vars = list(var_crs, var_land, var_longitude, var_latitude, var_n_ct)
  )

  # this is how GDAL writes CRS info
  ncatt_put(nc, var_crs, "spatial_ref", crs_chr)
  ncatt_put(nc, var_land, "grid_mapping", "crs")
  ncatt_put(nc, var_longitude, "grid_mapping", "crs")
  ncatt_put(nc, var_latitude, "grid_mapping", "crs")
  ncatt_put(nc, var_n_ct, "grid_mapping", "crs")

  ncvar_put(nc, var_land, vals = land_def[[1]])
  ncvar_put(nc, var_longitude, vals = coords$longitude)
  ncvar_put(nc, var_latitude, vals = coords$latitude)

  # write values one timestep at a time
  pb <- progress::progress_bar$new(total = length(dates_region))
  for (i in seq_along(dates_region)) {
    pb$tick()
    strs <- read_stars(n_ct_tif_region[i])
    vals <- strs[[1]]
    vals[is.na(vals)] <- 255L

    ncvar_put(
      nc,
      var_n_ct,
      vals,
      start = c(1, 1, i),
      count = c(-1, -1, 1)
    )
  }

  nc_close(nc)
}

if (!dir.exists("nc")) dir.create("nc")


regions <- unique(str_extract(basename(n_ct_tif_files), "^[A-Z]{2}"))

# can only paralellize here using regions because packing
# each NetCDF file has to be done sequentially
future::plan(future::multisession, workers = future::availableCores() - 1)
furrr::future_walk(regions, region_to_netcdf, .progress = TRUE)
