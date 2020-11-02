
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
    if (nrow(.x) == 0) return()
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

if (!dir.exists("gpkg")) {
  dir.create("gpkg")
}

# convert .e00 files to .gpkg
files_e00 <- tibble(
  file_real = list.files(exdir, pattern = "[0-9]{8}.*?\\.e00$", full.names = TRUE),
  file = basename(file_real)
) %>%
  left_join(zip_meta, by = "file") %>%
  mutate(gpkg_path = glue::glue("gpkg/{ region }_{ date }.gpkg")) %>%
  filter(!file.exists(gpkg_path))

for (i in seq_len(nrow(files_e00))) {
  message(
    glue::glue(
      "[{ i }/{ nrow(files_e00) }] { files_e00$file_real[i] } => { files_e00$gpkg_path[i] }"
    )
  )

  tryCatch({
    layer <- e00_read_sf(files_e00$file_real, layer = "PAL")

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
