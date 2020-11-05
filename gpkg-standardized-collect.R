
library(tidyverse)
# Note: the version of PROJ matters here because
# PROJ 6 and 7 handle the NAD27 -> WGS84 datum
# shift slightly differently. This is only important
# if more than one person/computer is writing the files
# so that they stay internally consistent (dd is using
# PROJ 6.3.1).
library(sf)

# three main CRSes used (there is one other CRS that was
# used in the great lakes region during 2014, but all files
# that have it are correctly labelled, so st_transform() should
# work)
cis_lcc_unknown_wkt <- 'PROJCS["unnamed",GEOGCS["Unknown datum based upon the Clarke 1866 ellipsoid",DATUM["Not_specified_based_on_Clarke_1866_ellipsoid",SPHEROID["Clarke 1866",6378206.4,294.978698213898]],PRIMEM["Greenwich",0],UNIT["degree",0.0174532925199433,AUTHORITY["EPSG","9122"]],AUTHORITY["EPSG","4008"]],PROJECTION["Lambert_Conformal_Conic_2SP"],PARAMETER["latitude_of_origin",40],PARAMETER["central_meridian",-100],PARAMETER["standard_parallel_1",49],PARAMETER["standard_parallel_2",77],PARAMETER["false_easting",0],PARAMETER["false_northing",0],UNIT["METERS",1],AXIS["Easting",EAST],AXIS["Northing",NORTH]]'
cis_lcc_nad27_wkt <- 'PROJCS["unnamed",GEOGCS["NAD27",DATUM["North_American_Datum_1927",SPHEROID["Clarke 1866",6378206.4,294.978698213898]],PRIMEM["Greenwich",0],UNIT["degree",0.0174532925199433,AUTHORITY["EPSG","9122"]],AUTHORITY["EPSG","4267"]],PROJECTION["Lambert_Conformal_Conic_2SP"],PARAMETER["latitude_of_origin",40],PARAMETER["central_meridian",-100],PARAMETER["standard_parallel_1",49],PARAMETER["standard_parallel_2",77],PARAMETER["false_easting",0],PARAMETER["false_northing",0],UNIT["METERS",1],AXIS["Easting",EAST],AXIS["Northing",NORTH]]'
cis_lcc_wgs84_wkt <- 'PROJCS["WGS_1984_Lambert_Conformal_Conic",GEOGCS["WGS 84",DATUM["WGS_1984",SPHEROID["WGS 84",6378137,298.257223563]],PRIMEM["Greenwich",0],UNIT["degree",0.0174532925199433,AUTHORITY["EPSG","9122"]],AUTHORITY["EPSG","4326"]],PROJECTION["Lambert_Conformal_Conic_2SP"],PARAMETER["latitude_of_origin",40],PARAMETER["central_meridian",-100],PARAMETER["standard_parallel_1",49],PARAMETER["standard_parallel_2",77],PARAMETER["false_easting",0],PARAMETER["false_northing",0],UNIT["metre",1,AUTHORITY["EPSG","9001"]],AXIS["Easting",EAST],AXIS["Northing",NORTH]]'

# the CRSes assigned to each file are probably correct
# but a few (8) are missing between 1980 and 1995. During this
# time, the most common CRS was the Unknown datum version of the LCC

# this loop (1) transforms everything to the latest version of the LCC (WGS84)
# and (2) checks to make sure geometries are valid (minimizes errors later)

standardize_gpkg <- function(file, dest, pb) {
  pb$tick()

  layer <- read_sf(file)
  if (is.na(st_crs(layer))) {
    st_crs(layer) <- st_crs(cis_lcc_unknown_wkt)
  }

  layer_wgs84 <- st_transform(layer, cis_lcc_wgs84_wkt)

  # the most common error here is a self-intersecting
  # polygon, which st_make_valid() splits into two
  layer_wgs84_valid <- st_make_valid(layer)

  write_sf(layer_wgs84, dest)
}

if (!dir.exists("gpkg-standardized")) dir.create("gpkg-standardized")

gpkg_files <- list.files("gpkg", "\\.gpkg$", full.names = TRUE)
gpkg_dest <- file.path("gpkg-standardized", basename(gpkg_files))

# make lazy so that this process can be cancelled/restarted
# takes ~1 second per file (delete gpkg-standardized to reset)
dest_exists <- file.exists(gpkg_dest)

walk2(
  gpkg_files[!dest_exists],
  gpkg_dest[!dest_exists],
  standardize_gpkg,
  pb = progress::progress_bar$new(total = length(gpkg_files))
)
