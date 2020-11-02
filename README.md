CIS Data Processing
================

This repo describes a pipeline for turning .zip files downloaded from
the [CIS search tool](https://iceweb1.cis.ec.gc.ca/Archive/page1.xhtml)
into usable data products that can be queried and loaded efficiently in
R. Roughly,

  - Add .zip files to zip/
  - Run zip-collect.R
  - Run gpkg-collect.R
  - Run attrs-collect.R

Both zip-collect.R and gpkg-collect.R are sufficiently lazy such that
they do not decompress/load anything that has already been converted.
The result is a folder gpkg/ that contains easy-to-read (i.e.,
`sf::read_sf()`) .gpkg files and a highly queryable attribute table
(read using `arrow::read_parquet()`).

Alternatively, you can use the provided attrs.parquet and/or
zip/meta.csv to download a subset of the data (urls for each data source
are provided).

``` r
library(tidyverse)

read_csv("zip/meta.csv")
```

    ## 
    ## -- Column specification --------------------------------------------------------
    ## cols(
    ##   region = col_character(),
    ##   date = col_date(format = ""),
    ##   zip_file = col_character(),
    ##   file = col_character(),
    ##   region_code = col_character(),
    ##   size = col_double(),
    ##   url = col_character()
    ## )

    ## # A tibble: 6,349 x 7
    ##    region date       zip_file    file      region_code   size url               
    ##    <chr>  <date>     <chr>       <chr>     <chr>        <dbl> <chr>             
    ##  1 EA     1968-06-25 zip/cis_ar~ rgc_a11_~ a11         9.59e5 https://ice-glace~
    ##  2 EA     1968-07-02 zip/cis_ar~ rgc_a11_~ a11         9.66e5 https://ice-glace~
    ##  3 EA     1968-07-11 zip/cis_ar~ rgc_a11_~ a11         1.02e6 https://ice-glace~
    ##  4 EA     1968-07-18 zip/cis_ar~ rgc_a11_~ a11         1.05e6 https://ice-glace~
    ##  5 EA     1968-07-25 zip/cis_ar~ rgc_a11_~ a11         1.11e6 https://ice-glace~
    ##  6 EA     1968-08-01 zip/cis_ar~ rgc_a11_~ a11         1.15e6 https://ice-glace~
    ##  7 EA     1968-08-08 zip/cis_ar~ rgc_a11_~ a11         1.20e6 https://ice-glace~
    ##  8 EA     1968-08-15 zip/cis_ar~ rgc_a11_~ a11         1.19e6 https://ice-glace~
    ##  9 EA     1968-08-22 zip/cis_ar~ rgc_a11_~ a11         1.15e6 https://ice-glace~
    ## 10 EA     1968-08-29 zip/cis_ar~ rgc_a11_~ a11         1.11e6 https://ice-glace~
    ## # ... with 6,339 more rows

``` r
sf::read_sf("gpkg/EA_1968-06-25.gpkg")
```

    ## Simple feature collection with 161 features and 66 fields
    ## geometry type:  POLYGON
    ## dimension:      XY
    ## bbox:           xmin: -294124.1 ymin: 2704501 xmax: 1856543 ymax: 5028246
    ## projected CRS:  unnamed
    ## # A tibble: 161 x 67
    ##       AREA PERIMETER ARCE00_COV. ARCE00_COV.ID A_LEGEND REGION DATE_CARTE SOURCE
    ##      <dbl>     <dbl>       <int>         <int> <chr>    <chr>  <chr>      <chr> 
    ##  1 1.75e11 11537280            2             2 Remote ~ AE     19680625   "RATI~
    ##  2 4.45e11  6040027            3             3 Land     AE     19680625   ""    
    ##  3 4.43e10  2580854            4             4 Land     AE     19680625   ""    
    ##  4 2.74e 6     6919.           5             5 No data  AE     19680625   ""    
    ##  5 1.65e11  7528443            6             6 Land     AE     19680625   ""    
    ##  6 6.42e 7    43507.           7             7 No data  AE     19680625   ""    
    ##  7 2.91e 8   155819.           8             8 No data  AE     19680625   ""    
    ##  8 4.02e10  3011698            9             9 Remote ~ AE     19680625   "RATI~
    ##  9 1.58e 7    19627.          10            10 No data  AE     19680625   ""    
    ## 10 1.34e 8    52649.          11            11 Land     AE     19680625   ""    
    ## # ... with 151 more rows, and 59 more variables: MOD <chr>, EGG.ID <int>,
    ## #   PNT_TYPE <int>, EGG_NAME <chr>, EGG_SCALE <int>, EGG_ATTR <chr>,
    ## #   USER_ATTR <chr>, ROTATION <int>, E_CT <chr>, E_CA <chr>, E_CB <chr>,
    ## #   E_CC <chr>, E_CD <chr>, E_SO <chr>, E_SA <chr>, E_SB <chr>, E_SC <chr>,
    ## #   E_SD <chr>, E_SE <chr>, E_FA <chr>, E_FB <chr>, E_FC <chr>, E_FD <chr>,
    ## #   E_FE <chr>, E_CS <chr>, R_CT <chr>, R_CMY <chr>, R_CSY <chr>, R_CFY <chr>,
    ## #   R_CGW <chr>, R_CG <chr>, R_CN <chr>, R_PMY <chr>, R_PSY <chr>, R_PFY <chr>,
    ## #   R_PGW <chr>, R_PG <chr>, R_PN <chr>, R_CS <chr>, R_SMY <chr>, R_SSY <chr>,
    ## #   R_SFY <chr>, R_SGW <chr>, R_SG <chr>, R_SN <chr>, N_CT <chr>, N_COI <chr>,
    ## #   N_CMY <chr>, N_CSY <chr>, N_CFY <chr>, N_CFY_TK <chr>, N_CFY_M <chr>,
    ## #   N_CFY_TN <chr>, N_CYI <chr>, N_CGW <chr>, N_CG <chr>, N_CN <chr>,
    ## #   N_CB <chr>, geom <POLYGON [m]>

``` r
arrow::read_parquet("attrs.parquet")
```

    ## # A tibble: 1,490,060 x 84
    ##    region date       row_id feat_xmin feat_ymin feat_xmax feat_ymax    AREA
    ##    <chr>  <date>      <int>     <dbl>     <dbl>     <dbl>     <dbl>   <dbl>
    ##  1 EA     1968-06-25      1  -294124.  3934064.   419601.  4653655  1.75e11
    ##  2 EA     1968-06-25      2   596533.  3983989.  1496861.  5028246. 4.45e11
    ##  3 EA     1968-06-25      3    63122.  4219701    316449.  4576497  4.43e10
    ##  4 EA     1968-06-25      4   111211.  4570884    113119.  4573562. 2.74e 6
    ##  5 EA     1968-06-25      5   157011.  4034862    580003.  4801968. 1.65e11
    ##  6 EA     1968-06-25      6   710912.  4864858.   725849   4876308. 6.42e 7
    ##  7 EA     1968-06-25      7   634969.  4816468.   699729   4838288  2.91e 8
    ##  8 EA     1968-06-25      8   450870.  4336518.   693837.  4818899  4.02e10
    ##  9 EA     1968-06-25      9   329870.  4677992    337830.  4683013  1.58e 7
    ## 10 EA     1968-06-25     10    71727.  4488232.    93600.  4498682. 1.34e 8
    ## # ... with 1,490,050 more rows, and 76 more variables: PERIMETER <dbl>,
    ## #   ARCE00_COV. <int>, ARCE00_COV.ID <int>, A_LEGEND <chr>, REGION <chr>,
    ## #   DATE_CARTE <chr>, SOURCE <chr>, MOD <chr>, EGG.ID <int>, PNT_TYPE <int>,
    ## #   EGG_NAME <chr>, EGG_SCALE <int>, EGG_ATTR <chr>, USER_ATTR <chr>,
    ## #   ROTATION <int>, E_CT <chr>, E_CA <chr>, E_CB <chr>, E_CC <chr>, E_CD <chr>,
    ## #   E_SO <chr>, E_SA <chr>, E_SB <chr>, E_SC <chr>, E_SD <chr>, E_SE <chr>,
    ## #   E_FA <chr>, E_FB <chr>, E_FC <chr>, E_FD <chr>, E_FE <chr>, E_CS <chr>,
    ## #   R_CT <chr>, R_CMY <chr>, R_CSY <chr>, R_CFY <chr>, R_CGW <chr>, R_CG <chr>,
    ## #   R_CN <chr>, R_PMY <chr>, R_PSY <chr>, R_PFY <chr>, R_PGW <chr>, R_PG <chr>,
    ## #   R_PN <chr>, R_CS <chr>, R_SMY <chr>, R_SSY <chr>, R_SFY <chr>, R_SGW <chr>,
    ## #   R_SG <chr>, R_SN <chr>, N_CT <chr>, N_COI <chr>, N_CMY <chr>, N_CSY <chr>,
    ## #   N_CFY <chr>, N_CFY_TK <chr>, N_CFY_M <chr>, N_CFY_TN <chr>, N_CYI <chr>,
    ## #   N_CGW <chr>, N_CG <chr>, N_CN <chr>, N_CB <chr>, EGG_ID <int>, R_CTK <chr>,
    ## #   R_CM <chr>, R_CTN <chr>, R_N1 <chr>, R_N2 <chr>, R_N3 <chr>, N_CVTK <chr>,
    ## #   N_CTK <chr>, N_CM <chr>, N_CTN <chr>

## Dataset details

A documentation of the vector file format (i.e., .gpkg files in gpkg/)
can be found
[here](https://www.jcomm.info/index.php?option=com_oe&task=viewDocumentRecord&docID=4439).
The column names are the same for files between 1968 and present, but in
2020 there was a shift in data formats and only some columns were
retained.

  - `E_CA` (Partial concentration of thickest ice): ’‘, ’1’, ‘2’, ‘3’,
    ‘4’, ‘5’, ‘6’, ‘7’, ‘8’, ‘9’
  - `E_CB` (Partial concentration of second thickest ice): ’‘, ’1’, ‘2’,
    ‘3’, ‘4’, ‘5’, ‘6’, ‘7’, ‘8’, ‘9’
  - `E_CC` (Partial concentration of the third thickest ice): ’‘, ’1’,
    ‘2’, ‘3’, ‘4’, ‘5’, ‘6’, ‘7’, ‘8’
  - `E_CD` (Stage of development of any remaining class of ice
    (corresponds to Sd): ’‘, ’1’, ‘2’, ‘3’, ‘4’, ‘5’, ‘6’
  - `E_CS`: ’‘, ’1’, ‘10’, ‘2’, ‘3’, ‘4’, ‘5’, ‘6’, ‘7’, ‘8’, ‘9’, ‘9+’
  - `E_CT` (Total concentration): ’‘, ’0.’, ‘1’, ‘10’, ‘2’, ‘3’, ‘4’,
    ‘5’, ‘6’, ‘7’, ‘8’, ‘9’, ‘9+’
  - `E_FA` (Form of thickest ice): ’‘, ’1’, ‘2’, ‘3’, ‘4’, ‘5’, ‘6’,
    ‘7’, ‘8’, ‘9’, ‘X’
  - `E_FB` (Form of second thickest ice): ’‘, ’1’, ‘2’, ‘3’, ‘4’, ‘5’,
    ‘6’, ‘7’, ‘8’, ‘9’, ‘X’
  - `E_FC` (Form of third thickest ice): ’‘, ’0’, ‘1’, ‘2’, ‘3’, ‘4’,
    ‘5’, ‘6’, ‘7’, ‘8’, ‘X’
  - `E_FD` (Form of any remaining class of ice): ’’
  - `E_FE`: ’’
  - `E_SA` Stage of development of thickest ice): ’‘, ’1’, ‘1.’, ‘3’,
    ‘4’, ‘4.’, ‘5’, ‘6’, ‘7’, ‘7.’, ‘8.’, ‘9.’
  - `E_SB` (Stage of development of second thickest Ice): ’‘, ’1’, ‘1.’,
    ‘2’, ‘4’, ‘4.’, ‘5’, ‘6’, ‘7’, ‘7.’, ‘8.’, ‘X’
  - `E_SC` (Stage of development of third thickest Ice): ’‘, ’1’, ‘1.’,
    ‘2’, ‘3’, ‘4’, ‘4.’, ‘5’, ‘7’
  - `E_SD` (Stage of development of any remaining class of ice): ’‘,
    ’1’, ‘4’, ‘4.’, ‘5’, ‘7’
  - `E_SE`: ’’
  - `E_SO`: ’‘, ’1.’, ‘4’, ‘4.’, ‘5’, ‘6’, ‘7’, ‘7.’, ‘8.’, ‘9.’
  - `N_CB`: ’‘,’ 0.2’, ‘10.0’
  - `N_CFY`: ’‘,’ 0.0’, ’ 0.3’, ’ 1.0’, ’ 1.3’, ’ 2.0’, ’ 2.3’, ’ 3.0’,
    ’ 3.3’, ’ 4.0’, ’ 4.3’, ’ 5.0’, ’ 5.3’, ’ 6.0’, ’ 6.3’, ’ 7.0’, ’
    7.3’, ’ 8.0’, ’ 8.3’, ’ 9.0’, ’ 9.3’, ’ 9.7’, ‘10.0’
  - `N_CG`: ’‘,’ 0.0’, ’ 0.3’, ’ 1.0’, ’ 2.0’, ’ 3.0’, ’ 4.0’, ’ 5.0’, ’
    6.0’, ’ 7.0’, ’ 8.0’, ’ 9.0’, ’ 9.7’, ‘10.0’
  - `N_CGW`: ’‘,’ 0.0’, ’ 0.3’, ’ 1.0’, ’ 2.0’, ’ 3.0’, ’ 4.0’, ’ 5.0’,
    ’ 6.0’, ’ 7.0’, ’ 8.0’, ’ 9.0’, ’ 9.7’, ‘10.0’
  - `N_CMY`: ’‘,’ 0.0’, ’ 0.3’, ’ 1.0’, ’ 2.0’, ’ 3.0’, ’ 4.0’, ’ 5.0’,
    ’ 6.0’, ’ 7.0’, ’ 8.0’, ’ 9.0’, ’ 9.7’, ‘10.0’
  - `N_CN`: ’‘,’ 0.0’, ’ 0.3’, ’ 1.0’, ’ 2.0’, ’ 3.0’, ’ 4.0’, ’ 5.0’, ’
    6.0’, ’ 7.0’, ’ 8.0’, ’ 9.0’, ’ 9.7’, ‘10.0’
  - `N_COI`: ’‘,’ 0.0’, ’ 0.3’, ’ 0.6’, ’ 1.0’, ’ 1.3’, ’ 2.0’, ’ 2.3’,
    ’ 3.0’, ’ 3.3’, ’ 4.0’, ’ 4.3’, ’ 5.0’, ’ 5.3’, ’ 6.0’, ’ 6.3’, ’
    7.0’, ’ 7.3’, ’ 8.0’, ’ 8.3’, ’ 9.0’, ’ 9.3’, ’ 9.7’, ‘10.0’
  - `N_CSY`: ’‘,’ 0.0’, ’ 0.3’, ’ 1.0’, ’ 2.0’, ’ 3.0’, ’ 4.0’, ’ 5.0’,
    ’ 6.0’, ’ 7.0’, ’ 8.0’, ’ 9.0’, ’ 9.7’, ‘10.0’
  - `N_CT`: ’‘,’ 0.0’, ’ 0.2’, ’ 0.3’, ’ 1.0’, ’ 2.0’, ’ 3.0’, ’ 4.0’, ’
    5.0’, ’ 6.0’, ’ 7.0’, ’ 8.0’, ’ 9.0’, ’ 9.7’, ‘10.0’
  - `N_CYI`: ’‘,’ 0.0’, ’ 0.3’, ’ 0.6’, ’ 1.0’, ’ 1.3’, ’ 2.0’, ’ 2.3’,
    ’ 3.0’, ’ 3.3’, ’ 4.0’, ’ 4.3’, ’ 5.0’, ’ 5.3’, ’ 6.0’, ’ 6.3’, ’
    7.0’, ’ 7.3’, ’ 8.0’, ’ 8.3’, ’ 9.0’, ’ 9.3’, ’ 9.7’, ‘10.0’
  - `R_CFY`: ’‘,’/‘, ’0’, ‘1’, ‘2’, ‘3’, ‘4’, ‘5’, ‘6’, ‘7’, ‘8’, ‘9’,
    ‘F’
  - `R_CG`: ’‘,’/‘, ’0’, ‘1’, ‘2’, ‘3’, ‘4’, ‘5’, ‘6’, ‘7’, ‘8’, ‘9’,
    ‘F’
  - `R_CGW`: ’‘,’/‘, ’0’, ‘1’, ‘2’, ‘3’, ‘4’, ‘5’, ‘6’, ‘7’, ‘8’, ‘9’,
    ‘F’
  - `R_CMY`: ’‘,’/‘, ’0’, ‘1’, ‘2’, ‘3’, ‘4’, ‘5’, ‘6’, ‘7’, ‘8’, ‘9’,
    ‘F’
  - `R_CN`: ’‘,’/‘, ’0’, ‘1’, ‘2’, ‘3’, ‘4’, ‘5’, ‘6’, ‘7’, ‘8’, ‘9’,
    ‘F’
  - `R_CS`: ’‘,’ 1’, ’ 2’, ’ 3’, ’ 4’, ’ 5’, ’ 6’, ’ 7’, ’ 8’, ’ 9’,
    ‘10’, ‘9+’
  - `R_CSY`: ’‘,’/‘, ’0’, ‘1’, ‘2’, ‘3’, ‘4’, ‘5’, ‘6’, ‘7’, ‘8’, ‘9’,
    ‘F’
  - `R_CT`: ’‘,’ 1’, ’ 2’, ’ 3’, ’ 4’, ’ 5’, ’ 6’, ’ 7’, ’ 8’, ’ 9’,
    ‘10’, ‘4’, ‘9+’
  - `R_PFY`: ’‘,’/‘, ’0’, ‘1’, ‘2’, ‘3’, ‘4’, ‘5’, ‘6’, ‘7’, ‘8’, ‘9’,
    ‘F’
  - `R_PG`: ’‘,’/‘, ’1’, ‘2’, ‘3’, ‘4’, ‘5’, ‘6’, ‘7’, ‘8’, ‘9’, ‘F’
  - `R_PGW`: ’‘,’/‘, ’0’, ‘1’, ‘2’, ‘3’, ‘4’, ‘5’, ‘6’, ‘7’, ‘8’, ‘9’,
    ‘F’
  - `R_PMY`: ’‘,’/‘, ’0’, ‘1’, ‘2’, ‘3’, ‘4’, ‘5’, ‘6’, ‘7’, ‘8’, ‘9’,
    ‘F’
  - `R_PN`: ’‘,’/‘, ’0’, ‘1’, ‘2’, ‘3’, ‘4’, ‘5’, ‘6’, ‘7’, ‘8’, ‘9’,
    ‘F’
  - `R_PSY`: ’‘,’/‘, ’0’, ‘1’, ‘2’, ‘3’, ‘4’, ‘5’, ‘6’, ‘7’, ‘8’, ‘9’,
    ‘F’
  - `R_SFY`: ’‘,’/‘, ’0’, ‘1’, ‘2’, ‘3’, ‘4’, ‘5’, ‘6’, ‘7’, ‘8’, ‘9’,
    ‘F’
  - `R_SG`: ’‘,’/‘, ’0’, ‘1’, ‘2’, ‘3’, ‘4’, ‘5’, ‘6’
  - `R_SGW`: ’‘,’/‘, ’0’, ‘1’, ‘2’, ‘3’, ‘5’, ‘6’
  - `R_SMY`: ’‘,’/‘, ’0’, ‘1’, ‘2’, ‘3’, ‘4’, ‘5’, ‘6’, ‘7’, ‘8’, ‘F’
  - `R_SN`: ’‘,’/‘, ’0’, ‘1’, ‘2’, ‘3’, ‘4’, ‘5’, ‘6’, ‘7’, ‘8’, ‘9’,
    ‘F’
  - `R_SSY`: ’‘,’/‘, ’0’, ‘1’, ‘2’, ‘3’, ‘4’, ‘6’, ‘F’

<!-- end list -->

``` r
attrs <- arrow::read_parquet("attrs.parquet")
colnames(attrs)

attrs %>% 
  select(matches("^[A-Z]_[A-Z]{2,3}$")) %>% 
  pivot_longer(everything()) %>% 
  distinct(name, value) %>% 
  arrange(name, value) %>% 
  group_by(name) %>% 
  summarise(
    values = paste0("'", value, "'", collapse = ", ")
  ) %>% 
  with(glue::glue("- `{ name }`: { values }")) %>% 
  glue::glue_collapse("\n") -> thing
```
