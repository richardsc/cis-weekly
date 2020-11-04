
library(tidyverse)

# github file limit
max_zip_size <- 90 * 1024 * 1024

zip_files <- tibble(
  file = list.files("zip", ".zip$", full.names = TRUE),
  size = file.size(file),
  is_too_big = size > max_zip_size
)

split_big_zip <- function(zip_file, remove = FALSE) {
  if (file.size(zip_file) <= max_zip_size) return()
  message(glue::glue("Splitting { zip_file } ({ round(file.size(zip_file) / 2^10, 1) }) MB"))

  tmp_extract <- tempfile()
  unzip(zip_file, exdir = tmp_extract)
  extract_files <- tibble(
    file = list.files(tmp_extract),
    size = file.size(file.path(tmp_extract, file)),
    cum_size = cumsum(size),
    group = 1
  )

  target_groups <- file.size(zip_file) %/% max_zip_size + 1
  target_size <- sum(extract_files$size) %/% target_groups

  while(any(extract_files$cum_size > target_size)) {
    extract_files <- extract_files %>%
      mutate(
        group = if_else(
          cum_size > target_size,
          max(group) + 1,
          group
        )
      ) %>%
      group_by(group) %>%
      mutate(cum_size = cumsum(size)) %>%
      ungroup()
  }

  extract_files %>%
    mutate(
      zipfile = zip_file %>%
        str_replace("\\.zip$", paste0(letters[group], ".zip")) %>%
        fs::path_abs()
    ) %>%
    group_by(zipfile) %>%
    group_walk(~{
      message(glue::glue("Writing '{ basename(.y$zipfile) }'"))
      withr::with_dir(tmp_extract, zip(.y$zipfile, .x$file))
    })

  if (remove) {
    message(glue::glue("Deleting '{ zip_file }'"))
    unlink(zip_file)
  }
}

processed_files <- zip_files %>%
  filter(is_too_big) %>%
  pull(file) %>%
  walk(split_big_zip, remove = TRUE)

# also list zip files and get meta, writing to zip/meta.csv
zip_meta <- tibble(
  zip = list.files("zip", ".zip$", full.names = TRUE),
  meta = map(zip, unzip, list = TRUE)
) %>%
  unnest(meta) %>%
  select(-Date) %>%
  rename(file = Name, file_size = Length) %>%
  # also add some information about each layer from the filename
  extract(
    file,
    c("region_code", "date", "region"),
    "_([a-z][0-9]{2})_([0-9]{8}).*?([A-Za-z]{2})\\.",
    remove = FALSE
  ) %>%
  mutate(
    file = file.path("file", file),
    date = lubridate::ymd(date),
    region = if_else(
      region == "XX",
      unname(c(a09 = "HB", a10 = "WA", a11 = "EA", a12 = "EC")[region_code]),
      toupper(region)
    ),
    # future vector file
    gpkg = glue::glue("gpkg/{ region }_{ date }.gpkg"),
    # helpful to have the shapefile name, which can be calculated
    # from the
    dsn = if_else(
      tools::file_ext(file) == "zip",
      sprintf(
        "file/%02d%02d%04d_CEXPR%s.shp",
        lubridate::day(date),
        lubridate::month(date),
        lubridate::year(date),
        region
      ),
      file
    ),
    aoi_number = str_extract(region_code, "[0-9]+"),
    url = glue::glue("https://ice-glaces.ec.gc.ca/www_archive/AOI_{ aoi_number }/Coverages/{ basename(file) }")
  ) %>%
  select(-aoi_number) %>%
  select(region, date, region_code, everything()) %>%
  arrange(region, date) %>%
  write_csv("zip/meta.csv")
