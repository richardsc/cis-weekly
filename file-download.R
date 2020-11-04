
library(tidyverse)

zip_meta <- read_csv("zip/meta.csv")

for (i in seq_len(nrow(zip_meta))) {
  message(glue::glue("[{ i }/{ nrow(zip_meta) }] '{ zip_meta$url[i] }' => '{ zip_meta$file[i] }'"))
  try(curl::curl_download(zip_meta$url[i], zip_meta$file[i]))
}

# recreate zip files according to zip_meta (which creates github-friendly
# sized zip files)
# zip_meta %>%
#   filter(file.exists(file)) %>%
#   group_by(zip) %>%
#   group_walk(~{
#     message(glue::glue("Writing '{ .y$zip }'"))
#     withr::with_dir("file", zip(.y$zip, basename(.x$file)))
#   })
