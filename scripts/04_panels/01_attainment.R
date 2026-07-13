# =========================================================================================================
# scripts/04_panels/01_attainment.R -- PM2.5 (2012 NAAQS) nonattainment TREATMENT, facility x year.
#   RUNS AFTER the facilities spine (needs facility coordinates).
#   in : data/raw/greenbook/pm25_2012_status/<year>.dbf   (yearly Green Book status snapshots, from Wayback)
#        data/raw/greenbook/pm25_2012_naa/PM25_2012Std_NAA.shp   (nonattainment-area polygons)
#        data/panels/spine.csv.gz   (facility coordinates)
#   out: data/panels/attainment.csv.gz   (one row per facility-year INSIDE a PM2.5 NAA)
#
#   COVERAGE / LIMITATIONS (deliberately narrow):
#     * PM2.5 (2012 standard) ONLY; ozone / SO2 / lead not built.
#     * Only the years with a Green Book snapshot; a single missing snapshot year is carried forward and
#       flagged `imputed`. Outside the window there is no PM2.5 status.
#     * SUB-COUNTY: a facility is placed by point-in-polygon against the actual NAA boundary (its exact
#       coordinate), not by county. Facilities without coordinates cannot be placed and are absent here.
#     * MAINTENANCE-AWARE: status = N (nonattainment) or M (maintenance, redesignated). A facility-year
#       ABSENT from this asset = the facility was not inside a PM2.5 NAA that year (i.e. attainment).
# =========================================================================================================
library(readr); library(dplyr); library(tidyr)
suppressPackageStartupMessages({library(foreign); library(sf)})
RAW <- here::here("data/raw"); PANELS <- here::here("data/panels")

status_dir <- file.path(RAW, "greenbook", "pm25_2012_status")
naa_shp    <- file.path(RAW, "greenbook", "pm25_2012_naa", "PM25_2012Std_NAA.shp")

# ---- 1. stack the yearly Green Book status snapshots -> area x year status (N/M) -------------------------
read_year <- function(f) {
  x <- foreign::read.dbf(f, as.is = TRUE); names(x) <- tolower(names(x))
  tibble::tibble(composid  = trimws(x$composid), area_name = trimws(x$area_name),
                 class     = trimws(x$class),    status    = trimws(x$naastatus),
                 year      = as.integer(tools::file_path_sans_ext(basename(f))))
}
obs       <- bind_rows(lapply(list.files(status_dir, "[.]dbf$", full.names = TRUE, ignore.case = TRUE), read_year))
obs_years <- sort(unique(obs$year))
areas     <- distinct(obs, composid, area_name)

# balanced area x year over the snapshot window; a missing snapshot year is carried forward (flagged)
ay <- expand_grid(composid = areas$composid, year = min(obs_years):max(obs_years)) |>
  left_join(select(obs, composid, year, status, class), by = c("composid", "year")) |>
  arrange(composid, year) |> group_by(composid) |>
  fill(status, class, .direction = "down") |> ungroup() |>
  mutate(imputed = !(year %in% obs_years)) |> left_join(areas, by = "composid")

# ---- 2. place facilities (spine coordinates) into a NAA polygon (composid) -------------------------------
shp <- st_read(naa_shp, quiet = TRUE); shp$COMPOSID <- trimws(shp$COMPOSID)
fac <- read_csv(file.path(PANELS, "spine.csv.gz"),
                col_types = cols(PGM_SYS_ID = col_character(), .default = col_guess()), show_col_types = FALSE) |>
  filter(!is.na(latitude), !is.na(longitude))
pts <- st_as_sf(fac, coords = c("longitude", "latitude"), crs = 4326) |> st_transform(st_crs(shp))
hit <- st_join(pts, shp["COMPOSID"], join = st_within) |> st_drop_geometry() |>
  filter(!is.na(COMPOSID)) |> transmute(PGM_SYS_ID, composid = trimws(COMPOSID)) |> distinct(PGM_SYS_ID, composid)

# ---- 3. facility x year status (facilities inside a PM2.5 NAA; absence elsewhere = attainment) -----------
att <- hit |> left_join(ay, by = "composid", relationship = "many-to-many") |>
  transmute(PGM_SYS_ID, year, composid, area_name, status, class, imputed) |>
  arrange(PGM_SYS_ID, year)

dir.create(PANELS, showWarnings = FALSE, recursive = TRUE)
write_csv(att, file.path(PANELS, "attainment.csv.gz"))
cat(sprintf("attainment: %d facility-years | %d facilities in a NAA | %d areas\n",
            nrow(att), n_distinct(att$PGM_SYS_ID), n_distinct(att$composid)))
