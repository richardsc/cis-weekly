
library(tidyverse)
library(sf)
library(stars)

# MS Daily Northern Hemisphere Snow and Ice Analysis at 1 km, 4 km, and 24 km Resolutions, Version 1
# https://nsidc.org/data/G02156/versions/1
# ftp://sidads.colorado.edu/pub/DATASETS/NOAA/G02156/

ims_daily_tif_url <- function(date, resolution = c("4km", "1km")) {
  resolution <- match.arg(resolution)
  server <- "ftp://sidads.colorado.edu/pub/DATASETS/NOAA/G02156"
  date_parts <- as.POSIXlt(date)
  year <- date_parts$year + 1900
  juld <- sprintf("%03d", date_parts$yday + 1)
  ver <- ifelse(date < "2014-12-02", "1.2.zip", "1.3.tif.gz")
  glue::glue("{ server }/GIS/{ resolution }/{ year }/ims{ year }{ juld }_{ resolution }_GIS_v{ ver }")
}

ims_daily_download <- function(date, resolution = c("4km", "1km"), quiet = FALSE) {
  resolution <- match.arg(resolution)
  url <- ims_daily_tif_url(date, resolution = resolution)
  local <- file.path("ims-daily-tif", "cache", str_extract(url, "GIS/.*"))
  if (!file.exists(local_tif)) {
    if (!quiet) message(url)
    try(curl::curl_download(url, local))
  }

  if (file.exists(local)) local else NA_character_
}


ims_files_4km <- tibble(
  date = seq(as.Date("2006-01-01"), Sys.Date() - 1, by = "day"),
  url = ims_daily_tif_url(date, resolution = "4km"),
  file = map_chr(date, ims_daily_download, resolution = "4km")
)

