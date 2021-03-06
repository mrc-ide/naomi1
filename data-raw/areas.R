#' Prepare areas dataset for Malawi
#'

library(tidyverse)
library(sf)
library(here)

devtools::load_all()

#' Construct 32 district shape file from GADM admin2 (https://gadm.org)
tmp <- tempfile()
download.file("https://biogeo.ucdavis.edu/data/gadm3.6/Rsf/gadm36_MWI_2_sf.rds", tmp)
sh2 <- readRDS(tmp)

#' ## Malawi (MWI)
#' Source: GADM Level 2 (https://biogeo.ucdavis.edu/data/gadm3.6/Rsf/gadm36_MWI_2_sf.rds)
#' Levels:
#'   * 1: Region
#'   * 2: Zone
#'   * 3: District
#'   * 4: District + 4 cities
#' Spectrum: National
#' EPP: Region (level 1)
#' EPP Urban/Rural: No
#' PEPFPAR PSNU: District (level 3)


mwi_wide <- sh2 %>%
  filter(TYPE_2 != "Water body" | NAME_1 == "Likoma") %>%
  mutate(district = NAME_1,
         district32 = case_when(TYPE_2 == "City" ~ NAME_2,
                                TRUE ~ NAME_1),
         zone = district %>% fct_collapse(
           "Northern" = c("Chitipa", "Karonga", "Likoma", "Mzimba", "Nkhata Bay", "Rumphi"),
           "Central-East" = c("Dowa", "Kasungu", "Nkhotakota", "Ntchisi", "Salima"),
           "Central-West" = c("Dedza", "Lilongwe", "Mchinji", "Ntcheu"),
           "South-East" = c("Balaka", "Machinga", "Mangochi", "Mulanje", "Phalombe", "Zomba"),
           "South-West" = c("Blantyre", "Chikwawa", "Chiradzulu", "Mwanza", "Neno", "Nsanje", "Thyolo")
         ) %>%
           fct_relevel("Northern", "Central-East", "Central-West", "South-East", "South-West"),
         region = zone %>% fct_collapse("Central" = c("Central-East", "Central-West"), "Southern" = c("South-East", "South-West")) %>%
           fct_relevel("Northern", "Central", "Southern")
  ) %>%
  group_by(region, zone, district, district32) %>%
  summarise() %>%
  ungroup %>%
  arrange(region, zone, -map_dbl(geometry, ~st_centroid(.x)[[2]])) %>%
  transmute(
    name0 = "Malawi",
    id0 = "MWI",
    name1 = region,
    id1 = paste0("MWI_1_", as.integer(as_factor(name1))),
    name2 = zone,
    id2 = paste0("MWI_2_", as.integer(as_factor(name2))),
    name3 = district,
    id3 = paste0("MWI_3_", as.integer(as_factor(name3))),
    name4 = district32,
    id4 = paste0("MWI_4_", as.integer(as_factor(name4))),
    spectrum_region_code = 0
  )

mwi_simple <- mwi_wide %>% rmapshaper::ms_simplify(0.1)

check_boundaries(mwi_wide, mwi_simple)
pryr::object_size(mwi_wide %>% select)
pryr::object_size(mwi_simple %>% select)


mwi <- gather_areas(mwi_simple) %>%
  mutate(area_sort_order = row_number(),
         area_level = as.integer(area_level))

area_hierarchy <- mwi %>%
  mutate(center = st_point_on_surface(mwi$geometry),
         center_x = st_coordinates(center)[,1],
         center_y = st_coordinates(center)[,2],
         center = NULL) %>%
  as.data.frame %>%
  select(-geometry)

areas <- mwi %>%
  select(-area_level, -parent_area_id, -area_sort_order) %>%
  group_by(area_id) %>%
  filter(row_number() == 1) %>%
  left_join(
    st_point_on_surface(.) %>%
    rename(center = geometry) %>%
    as.data.frame()
  ) %>%
  ungroup

area_boundaries <- mwi %>%
  select(area_id, geometry)

area_levels <- mwi %>%
  as.data.frame() %>%
  count(area_level, name = "n_areas") %>%
  arrange(area_level) %>%
  mutate(area_level_label = area_level %>% recode(`0` = "Country", `1` = "Region", `2` = "Zone", `3` = "District", `4` = "District + Metro"),
         display = TRUE,
         spectrum_level = if_else(area_level == 0, TRUE, FALSE),
         epp_level = if_else(area_level == 1, TRUE, FALSE),
         epp_urban_rural = FALSE,
         naomi_level = if_else(area_level == 4, TRUE, FALSE),
         pepfar_psnu_level = if_else(area_level == 3, TRUE, FALSE))

#' Plot illustrating joining of area datasets

area_hierarchy %>%
  left_join(area_levels %>% select(area_level, area_level_label)) %>%
  mutate(area_level_label = area_level_label %>% fct_reorder(area_level)) %>%
  ggplot() +
  geom_sf(data = . %>% left_join(area_boundaries) %>% st_as_sf()) +
  geom_label(aes(center_x, center_y, label = area_sort_order)) +
  facet_wrap(~area_level_label, nrow = 1) +
  th_map()

#' ## Save datasets

mwi_area_levels <- area_levels
mwi_area_hierarchy <- area_hierarchy
mwi_area_boundaries <- area_boundaries

usethis::use_data(
           mwi_area_levels,
           mwi_area_hierarchy,
           mwi_area_boundaries,
           overwrite = TRUE
         )

dir.create(here("inst/extdata/areas"))

write_csv(area_levels, here("inst/extdata/areas/area_levels.csv"), na = "")
write_csv(area_hierarchy, here("inst/extdata/areas/area_hierarchy.csv"), na = "")

st_write(area_boundaries, here("inst/extdata/areas/area_boundaries.geojson"), delete_dsn = TRUE)

#' # Webtool single GeoJSON input
#'
#' The 2019 version of Naomi web tool allows upload of a single GeoJSON file for
#' specifying the area hierarchy. 

area_merged <- area_hierarchy %>%
  left_join(
    area_levels %>% select(area_level, area_level_label, display, naomi_level)
  ) %>%
  left_join(
    area_boundaries
  )

##+ message = FALSE
st_write(area_merged, here("inst/extdata/areas/area_merged.geojson"), delete_dsn = TRUE)


#' ## Table schema

library(tableschema.r)

schema_area_meta <- system.file("extdata/areas/area_meta.csv", package = "naomi") %>%
  tableschema.r::infer()

schema_area_hierarchy <- system.file("extdata/areas/area_hierarchy.csv", package = "naomi") %>%
  tableschema.r::infer() %>%
  jsonlite::toJSON(pretty = TRUE)

schema_area_names <- system.file("extdata/areas/area_names.csv", package = "naomi") %>%
  tableschema.r::infer() %>%
  jsonlite::toJSON(pretty = TRUE)

schema_area_names <- system.file("extdata/areas/area_hierarchy.csv", package = "naomi") %>%
  tableschema.::infer() %>%
  jsonlite::toJSON(pretty = TRUE)

#' I cant figure out how to get tableschema.r to parse geojson...

schema_area_booundaries <-
  '{
    "fields": [
      {
        "name": ["iso3"],
        "type": ["string"],
        "format": ["default"]
      },
      {
        "name": ["area_id"],
        "type": ["string"],
      "format": ["default"]
    },
    {
      "name": ["geometry"],
      "type": ["geojson"],
      "format": ["default"]
    }
  ],
  "missingValues": [
    [""]
  ]
}
'

schema_area_centers <-
'{
    "fields": [
      {
        "name": ["iso3"],
        "type": ["string"],
        "format": ["default"]
      },
      {
        "name": ["area_id"],
        "type": ["string"],
      "format": ["default"]
    },
    {
      "name": ["geometry"],
      "type": ["geopoint"],
      "format": ["default"]
    }
  ],
  "missingValues": [
    [""]
  ]
}
'

#' Still working on this...
