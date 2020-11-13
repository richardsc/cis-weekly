
library(tidyverse)
library(stars)
library(ncdf4)

n_ct_tif_files <- list.files("tif/n-ct", "\\.tif$", full.names = TRUE)

if (!dir.exists("nc")) dir.create("nc")

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

  # This is a dummy variable whose attribute 'spatial_ref' carries the CRS.
  # Other variables must have an attribute 'grid_mapping' whose value is the
  # name of this variable.
  var_crs <- ncvar_def(
    "crs",
    units = "",
    dim = list(),
    prec = "integer"
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
    vars = list(var_crs, var_longitude, var_latitude, var_n_ct)
  )

  # this is how GDAL writes CRS info
  ncatt_put(nc, var_crs, "spatial_ref", crs_chr)
  ncatt_put(nc, var_longitude, "grid_mapping", "crs")
  ncatt_put(nc, var_latitude, "grid_mapping", "crs")
  ncatt_put(nc, var_n_ct, "grid_mapping", "crs")

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

regions <- unique(str_extract(basename(n_ct_tif_files), "^[A-Z]{2}"))

# can only paralellize here using regions because packing
# each NetCDF file has to be done sequentially
future::plan(future::multisession, workers = future::availableCores() - 1)
furrr::future_walk(regions, region_to_netcdf, .progress = TRUE)
