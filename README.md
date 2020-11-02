
# cis-weekly

## 01.R

Processes new files in the zip/ directory such that they are small enough to fit under the GitHub 100 MB size limit. Also generates zip/meta.csv, which list files available in each zip file.

## 03.R

For new or changed files in the zip/ folder, read each layer and write as a .gpkg file. Updates the gpkg/meta.csv file, which lists column names available in each file.

## 04.R

Rasterizes a specific set of columns, writing to the tif/ folder.
