
library(tidyverse)
library(sf)
library(arce00) # remotes::install_github("paleolimbot/arce00")

study_crs <- st_crs("ESRI:102002")
zip_meta <- read_csv("zip/meta.csv")

# extract .zip files from the search tool into temp-exdir
# only if there isn't a corresponding .gpkg and the file
# hasn't been previously extracted
exdir <- "temp-exdir"
if (!dir.exists(exdir)) dir.create(exdir)

existing_files <- list.files(exdir)

zip_meta %>%
  filter(
    !file.exists(file.path(exdir, file)),
    !file.exists(file.path("gpkg", gpkg))
  )  %>%
  group_by(zip_file) %>%
  group_walk(~{
    if (nrow(.x) == 0) return()
    message(glue::glue("Extracting { length(.x$file) } files from { .y$zip_file }"))
    unzip(.y$zip_file, .x$file, exdir = exdir)
  })

# .zip files get extracted to .shp files
# use the existence of a .shp file to skip extraction
zip_meta %>%
  filter(
    tools::file_ext(file) == "zip",
    !file.exists(file.path(exdir, dsn)),
    !file.exists(file.path("gpkg", gpkg))
  ) %>%
  mutate(file = file.path(exdir, file)) %>%
  pull(file) %>%
  walk(unzip, exdir = exdir)

if (!dir.exists("gpkg")) {
  dir.create("gpkg")
}

# convert .e00 files to .gpkg
files_e00 <- tibble(
  file_real = list.files(exdir, pattern = "[0-9]{8}.*?\\.e00$", full.names = TRUE),
  file = basename(file_real)
) %>%
  # less reliable, but allows dropping of missing .e00 files
  # into temp-exdir
  extract(file, "date_fn", "([0-9]{8})", remove = F) %>%
  extract(file, "region_fn", "([A-Z]{2})\\.e00", remove = F) %>%
  left_join(zip_meta, by = "file") %>%
  mutate(
    date = coalesce(date, lubridate::ymd(date_fn)),
    region = coalesce(region, region_fn),
    gpkg_path = glue::glue("gpkg/{ region }_{ date }.gpkg")
  ) %>%
  filter(!file.exists(gpkg_path))

for (i in seq_len(nrow(files_e00))) {
  message(
    glue::glue(
      "[{ i }/{ nrow(files_e00) }] { files_e00$file_real[i] } => { files_e00$gpkg_path[i] }"
    )
  )

  tryCatch({
    layer <- e00_read_sf(files_e00$file_real[i], layer = "PAL")

    # drop the ArcIds column (is dropped anyway on write)
    if ("ArcIds" %in% names(layer)) {
      layer <- layer[setdiff(names(layer), "ArcIds")]
    }

    write_sf(layer, files_e00$gpkg_path[i])

  }, error = function(e) {
    unlink(files_e00$gpkg_path[i])
    msg <- paste0(format(e), collapse = "\n")
    message(glue::glue("Error on layer '{ files_e00$file[i] }': { msg }"))
  })
}

files_shp <- tibble(
  file_real = list.files(exdir, pattern = "[0-9]{8}.*?\\.shp$", full.names = TRUE),
  dsn = basename(file_real)
) %>%
  # less reliable, but allows downloading missing .zip files
  # into temp-exdir
  extract(dsn, "date_fn", "([0-9]{8})", remove = F) %>%
  extract(dsn, "region_fn", "([A-Z]{2})\\.shp", remove = F) %>%
  left_join(zip_meta, by = "dsn") %>%
  mutate(
    date = coalesce(date, lubridate::dmy(date_fn)),
    region = coalesce(region, region_fn),
    gpkg_path = glue::glue("gpkg/{ region }_{ date }.gpkg")
  ) %>%
  filter(!file.exists(gpkg_path))

for (i in seq_len(nrow(files_shp))) {
  message(
    glue::glue(
      "[{ i }/{ nrow(files_shp) }] { files_shp$file_real[i] } => { files_shp$gpkg_path[i] }"
    )
  )

  tryCatch({
    layer <- read_sf(files_shp$file_real[i])

    # the PNT_TYPE column needs to be numeric to be combinable
    # with the e00 tables
    if ("PNT_TYPE" %in% names(layer)) {
      layer$PNT_TYPE <- as.numeric(layer$PNT_TYPE)
    }

    write_sf(layer, files_shp$gpkg_path[i])

  }, error = function(e) {
    unlink(files_shp$gpkg_path[i])
    msg <- paste0(format(e), collapse = "\n")
    message(glue::glue("Error on layer '{ files_shp$file[i] }': { msg }"))
  })
}

# generate geopackage meta
geom_sum <- function(x, pb) {
  pb$tick()
  as_tibble(vapour::vapour_geom_summary(x))
}
summary <- tibble(
  gpkg = list.files("gpkg", "\\.gpkg$", full.names = TRUE),
  summary = map(gpkg, geom_sum, pb = progress::progress_bar$new(total = length(gpkg)))
)

gpkg_meta <- summary %>%
  mutate(
    gpkg_size = file.size(gpkg),
    summary = map(
      summary,
      ~tibble(
        gpkg_n_features = nrow(.x),
        gpkg_xmin = min(.x$xmin),
        gpkg_ymin = min(.x$ymin),
        gpkg_xmax = max(.x$xmax),
        gpkg_ymax = max(.x$ymax)
      )
    )
  ) %>%
  unnest(summary) %>%
  write_csv("gpkg/meta.csv")
