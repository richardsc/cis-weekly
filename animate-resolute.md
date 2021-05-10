
# Animate Resolute

``` r
library(tidyverse)
```

    ## ── Attaching packages ─────────────────────────────────────── tidyverse 1.3.0 ──

    ## ✓ ggplot2 3.3.2     ✓ purrr   0.3.4
    ## ✓ tibble  3.1.1     ✓ dplyr   1.0.2
    ## ✓ tidyr   1.1.2     ✓ stringr 1.4.0
    ## ✓ readr   1.4.0     ✓ forcats 0.5.0

    ## ── Conflicts ────────────────────────────────────────── tidyverse_conflicts() ──
    ## x dplyr::filter() masks stats::filter()
    ## x dplyr::lag()    masks stats::lag()

``` r
library(sf)
```

    ## Linking to GEOS 3.8.0, GDAL 3.0.4, PROJ 6.3.1

``` r
library(stars)
```

    ## Loading required package: abind

``` r
knitr::opts_chunk$set(echo = TRUE)
```

``` r
# https://www.openstreetmap.org/export#map=6/74.937/-91.989
aoi <- st_bbox(
  c(xmin = -103.3, ymin = 72.5, xmax = -80.618, ymax = 77.030),
  crs = 4326
)

target_crs <- st_crs(read_stars("tif/e-ct/EA_1968-06-25_e-ct.tif"))
aoi_crs <- aoi %>% 
  st_as_sfc() %>%
  st_set_crs(NA_crs_) %>% 
  st_segmentize(0.01) %>%
  st_set_crs(4326) %>% 
  st_transform(target_crs) %>% 
  st_bbox()


aoi_target <- st_as_stars(aoi_crs, values = 255, dx = 1000, dy = 1000)
```

``` r
files <- tibble(
  path = list.files("tif/n-ct", pattern = "^(EA|WA)", full.names = TRUE),
  file = basename(path)
) %>% 
  separate(file, c("region", "date", "type"), sep = "_") %>% 
  transmute(path, region, date = as.Date(date)) %>% 
  filter(region %in% c("EA", "WA"))

weeks <- tibble(
  start = seq(as.Date("1998-01-01"), Sys.Date(), by = "week"),
  end = start + 6L,
  files = map2(start, end, ~filter(files, date >= .x, date <= .y)),
  n_files = map_int(files, nrow)
)
```

``` r
aggregated <- NULL

for (i in seq_len(nrow(weeks))) {
  files <- weeks$files[[i]]$path %>% 
    map(read_stars, proxy = TRUE) %>% 
    map(st_warp, aoi_target, use_gdal = TRUE)
  
  title <- sprintf("%s to %s [%d]", weeks$start[i], weeks$end[i], length(files))
  
  if (is.null(aggregated)) {
    aggregated <- files[[1]]
    aggregated[[1]][] <- NA_real_
  }
  
  # aggregate files (use last frame if there are zero files for the week)
  if (length(files) > 0) {
    # a cheap way of aggregating...use the first non-missing value
    raw_values <- files %>% 
      map(~na_if(as.numeric(unclass(.x)[[1]]), 255))
    aggregated[[1]][] <- coalesce(!!! raw_values)
  }
  
  # plot.stars() doesn't allow a background color, hence the
  # colour palette
  plot(
    aggregated,
    breaks = c(seq(0, 90, 10), 95, 101),
    col = viridisLite::plasma(11),
    key.pos = 4,
    main = title
  )
}
```

![](animate-resolute_files/figure-gfm/unnamed-chunk-3-.gif)<!-- -->
