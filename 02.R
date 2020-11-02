library(tidyverse)
library(sf)
library(arce00) # remotes::install_github("paleolimbot/arce00")

study_crs <- st_crs("ESRI:102002")
zip_meta <- read_csv("zip/meta.csv")

# extract .zip files from the search tool into temp-exdir
exdir <- "temp-exdir"
if (!dir.exists(exdir)) dir.create(exdir)

existing_files <- list.files(exdir)

zip_meta %>%
  filter(!(file %in% existing_files)) %>%
  group_by(zip_file) %>%
  group_walk(~{
    message(glue::glue("Extracting { length(.x$file) } files from { .y$zip_file }"))
    unzip(.y$zip_file, .x$file, exdir = exdir)
  })

# may contain .e00 files and .zip files
# need to unzip the zip files (which contain .shp files)
shp_zip <- list.files(exdir, "\\.zip$", full.names = TRUE)
for (zip in shp_zip) {
  message(glue::glue("Extracting '{ zip }' to '{ exdir }'"))
  unzip(zip, exdir = exdir, overwrite = FALSE)
}

# list layers (.shp or .e00)
files_e00 <- list.files(exdir, pattern = "[0-9]{8}.*?\\.e00$", full.names = TRUE)
files_shp <- list.files(exdir, pattern = "[0-9]{8}.*?\\.shp$", full.names = TRUE)

# load all .e00 files (~1 sec per file, so use progress bar)
pb <- progress::progress_bar$new(total = length(files_e00))
read_e00 <- function(file) {
  if (interactive()) pb$tick()
  e00_read_sf(file, layer = "PAL")
}
layers_e00 <- map(
  set_names(files_e00),
  # NULL on failure instead of stopping
  possibly(read_e00, NULL)
)

# some fail to load because the files are incomplete
# list these and warn, but skip
bad_e00_layers <- map_lgl(layers_e00, is.null)
if (any(bad_e00_layers)) {
  bad_files <- paste0(files_e00[bad_e00_layers], collapse = "\n")
  message(glue::glue("Couldn't read the following files:\n{ bad_files }"))
}

layers_e00 <- layers_e00[!bad_e00_layers]

# load all .shp files
pb <- progress::progress_bar$new(total = length(files_shp))
read_shp <- function(file) {
  if (interactive()) pb$tick()
  read_sf(file)
}
layers_shp <- map(set_names(files_shp), read_shp)

# helpers to extract dates/regions from filenames
extract_region <- function(file) {
  matched <- stringr::str_match(basename(file), "([a-zA-Z]{2})\\.(shp|e00)")
  stringr::str_to_upper(matched[, 2, drop = TRUE])
}

extract_date <- function(file) {
  is_shp <- tools::file_ext(file) == "shp"
  matched <- stringr::str_extract(basename(file), "[0-9]{8}")
  out <- rep(as.Date(NA_character_), length(file))
  out[is_shp] <- lubridate::dmy(matched[is_shp])
  out[!is_shp] <- lubridate::ymd(matched[!is_shp])
  out
}

# For each layer, transform to the study CRS, clip to the study
# area, and write to gpkg.
# Make PNT_TYPE character (because the layers won't rbind otherwise).
layers_all <- c(layers_e00, layers_shp)
if (!dir.exists("gpkg")) dir.create("gpkg")
pb <- progress::progress_bar$new(total = length(layers_all))
for (i in seq_along(layers_all)) {
  if (interactive()) pb$tick()

  file <- names(layers_all)[i]
  layer <- layers_all[[i]]
  date <- extract_date(file)
  region <- extract_region(file)
  stopifnot(!is.na(date), !is.na(region))

  # drop the ArcIds column if it exists (is dropped anyway on write)
  if ("ArcIds" %in% names(layer)) {
    layer <- layer[setdiff(names(layer), "ArcIds")]
  }

  tryCatch({
    layer <- layer %>%
      # Some polygons may be invalid, and GEOS will not operate on them
      st_transform(study_crs) %>%
      st_make_valid() %>%
      mutate(
        PNT_TYPE = as.character(PNT_TYPE)
      )

    write_sf(layer, glue::glue("data/poly/{ region }_{ date }.gpkg"))
  }, error = function(e) {
    message(glue::glue("Error for layer '{ file }': { e }"))
  })
}
