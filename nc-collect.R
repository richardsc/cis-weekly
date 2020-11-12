
library(tidyverse)
library(stars)
library(ncdf4)

n_ct_tif_files <- list.files("tif/n-ct", "\\.tif$", full.names = TRUE)
regions <- unique(str_extract(basename(n_ct_tif_files), "^[A-Z]{2}"))

if (!dir.exists("nc")) dir.create("nc")

for (region in regions) {
  if (file.exists(glue::glue("nc/{ region }.nc"))) {
    next
  }

  n_ct_tif_region <- n_ct_tif_files[str_starts(basename(n_ct_tif_files), region)]
  dates_region <- as.Date(str_extract(basename(n_ct_tif_region), "[0-9-]{10}"))

  tif0 <- read_stars(n_ct_tif_region[1])
  crs_chr <- st_crs(tif0)$proj4string

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

  # This is a dummy variable whose attribute 'proj4' carries the CRS
  # info. Redundantly, the 'proj4' attribute of other variables along
  # the x-y grid is also set to this.
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
    prec = "float"
  )

  var_latitude <- ncvar_def(
    "latitude",
    units = "degrees",
    dim = list(dim_x, dim_y),
    longname = "Latitude (WGS84)",
    prec = "float"
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
  ncatt_put(nc, var_crs, "proj4", crs_chr)
  ncatt_put(nc, var_longitude, "grid_mapping", "crs")
  ncatt_put(nc, var_longitude, "proj4", crs_chr)
  ncatt_put(nc, var_latitude, "grid_mapping", "crs")
  ncatt_put(nc, var_latitude, "proj4", crs_chr)
  ncatt_put(nc, var_n_ct, "grid_mapping", "crs")
  ncatt_put(nc, var_n_ct, "proj4", crs_chr)

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
