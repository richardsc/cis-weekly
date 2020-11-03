
library(tidyverse)

# download files
# doesn't currently incorporate the inconsistencies for some files
# but probably works for recent files (tested 2016-present)
date_start <- "1968-06-25"
date_end <- Sys.Date()
regions <- c("EA", "EC", "GL", "HB", "WA")

# helper: returns all mondays between (and including) start and end
cis_weekly_date <- function(start, end) {
  start <- as.Date(start)
  start_mon <- lubridate::ceiling_date(
    as.Date(start),
    "week",
    week_start = 1,
    change_on_boundary = FALSE
  )
  end <- as.Date(end)

  if (end <= start) {
    return(as.Date(character(0)))
  }

  seq(start_mon, end, by = 7L)
}

region_codes <- c(
  "EA" = "a11",
  "EC" = "a12",
  "GL" = "a13",
  "HB" = "a09",
  "WA" = "a10"
)[regions]

e00_dates <- cis_weekly_date(date_start, "2020-01-13")

e00_info <- crossing(
  tibble(
    region = names(region_codes),
    region_code = unname(region_codes),
    region_num = region_code %>%
      str_extract("[0-9]+") %>%
      as.numeric() %>%
      sprintf("%02d", .)
  ),
  tibble(
    date = e00_dates
  )
) %>%
  mutate(
    year = lubridate::year(date),
    month = lubridate::month(date),
    day = lubridate::day(date),
    date_smush = sprintf("%04d%02d%02d", year, month, day),
    url = glue::glue(
      paste0(
        "https://ice-glaces.ec.gc.ca/",
        "www_archive/AOI_{ region_num }/Coverages/",
        "rgc_{ region_code }_{ date_smush}_CEXPR{ region }.e00"
      )
    ),
    dest = glue::glue("file/rgc_{ region_code }_{ date_smush}_CEXPR{ region }.e00")
  )

e00_download <- e00_info %>%
  filter(!file.exists(dest))

for (i in seq_len(nrow(e00_download))) {
  message(glue::glue("[{ i }/{ nrow(e00_download) }]'{ e00_download$url[i] }' => '{ e00_download$dest[i] }'"))
  try(curl::curl_download(e00_download$url[i], e00_download$dest[i]))
}

# starts on Jan 20th 2020
shp_dates <- cis_weekly_date("2020-01-19", Sys.Date())

shp_info <- crossing(
  tibble(
    region = names(region_codes),
    region_code = unname(region_codes),
    region_num = region_code %>%
      str_extract("[0-9]+") %>%
      as.numeric() %>%
      sprintf("%02d", .)
  ),
  tibble(
    date = shp_dates
  )
) %>%
  mutate(
    year = lubridate::year(date),
    month = lubridate::month(date),
    day = lubridate::day(date),
    date_smush = sprintf("%04d%02d%02d", year, month, day),
    url = glue::glue(
      paste0(
        "https://ice-glaces.ec.gc.ca/",
        "www_archive/AOI_{ region_num }/Coverages/",
        "rgc_{ region_code }_{ date_smush}_CEXPR{ region }.zip"
      )
    ),
    dest = glue::glue("file/rgc_{ region_code }_{ date_smush}_CEXPR{ region }.zip")
  )

shp_download <- shp_info %>% filter(!file.exists(dest))

for (i in seq_len(nrow(shp_download))) {
  message(glue::glue("[{ i }/{ nrow(shp_download) }]'{ shp_download$url[i] }' => '{ shp_download$dest[i] }'"))
  try(curl::curl_download(shp_download$url[i], shp_download$dest[i]))
}

# zip files by year
rbind(e00_info, shp_info) %>%
  filter(file.exists(dest)) %>%
  mutate(zipfile = fs::path_abs(glue::glue("zip/cis_arc_{ year }.zip"))) %>%
  group_by(zipfile) %>%
  group_walk(~{
    withr::with_dir("file", zip(.y$zipfile, basename(.x$dest)))
  })
