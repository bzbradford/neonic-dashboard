# Neonic Dashboard — R Prototype Plan

R-first prototype of the Wisconsin neonicotinoid water monitoring dashboard described in `SPEC.md`. The Svelte/Node stack notes in SPEC §1–2, §4 (file formats), and §6.4 are set aside. The **data-handling rules (§5), app content (§6), and design tokens (§7)** still apply and carry over to R.

Reference projects (read-only):
- `../WAV Dashboard/app`: Shiny layout (`global.R` / `ui.R` / `server.R`, numbered modules in `src/`), bslib, `setup.R` → `.RData`, Red Hat fonts + UW red header, `?stn=` URL state, plotly charts, DT tables.
- `../WAV Analysis Quarto Website`: `setup_*.R` → `.RData` → `.qmd`, `mapgl` (MapLibre + Carto Positron) maps with county/watershed choropleths, ggplot static maps, gt/DT tables, `freeze: auto`, `echo: false`.

---

## Phases

| # | Phase | Main output | Gate |
|---|---|---|---|
| 1 | Data load & prep | `R/prep_data.R` → `app/data.RData` + validation report | Ben confirms the decisions in §3 |
| 2 | Analysis document | `analysis.qmd` → `analysis.html` | Ben reviews the figures and tables and picks what goes in the app |
| 3 | Shiny app | `app/` (global/ui/server/src/www) | Runs locally and deploys to Connect |

---

## 1. Data inventory (from profiling, 2026-09-30)

### Groundwater: `data/neonic_data_groundwater.csv`
- 24,861 rows; 2,188 wells (`WUWN`); 2006-11-06 → 2025-12-03 (only ~90 rows before 2011).
- Long format: one row per well × date × analyte. Units are all `µg/L` (= ppb, so the threshold file needs no conversion).
- Well metadata: `WellUse` (Private Potable 16,948 rows, Monitoring Well 6,878, Piezometer 996, Private Non-potable 39), plus `WellDepth`, `CasingDepth`, `BedrockDepth` and `StaticWaterDepth` (these are 40–85% missing).
- **15 exact duplicate rows**, plus 3 more well × date × analyte keys with conflicting rows. A few sample events have 10–12 analyte rows, which means repeated same-day samples.

### Surface water: `data/neonic_data_surfacewater.csv`
- 8,267 rows; 147 stations (`StationID`) but only 141 unique names (some names are shared, so labels need the ID); 2011-03-08 → 2025-12-01.
- No duplicates. 70 early events tested thiamethoxam only; later events tested 5–6 analytes.

### Analytes: 6 present, SPEC assumed 3
| Analyte | GW detects / n | SW detects / n | Benchmarks in thresholds file |
|---|---|---|---|
| Imidacloprid | 718 / 4,301 | 115 / 1,401 | all 4 |
| Clothianidin | 1,142 / 4,262 | 227 / 1,401 | all 4 |
| Thiamethoxam | 688 / 4,299 | 240 / 1,471 | all 4 |
| Dinotefuran | 4 / 4,220 | 2 / 1,401 | none |
| Acetamiprid | 0 / 4,257 | 0 / 1,401 | aquatic only |
| Thiacloprid | 0 / 3,522 | 0 / 1,192 | none |

### Non-detects and detection limits
- Non-detects are coded as `Result = 0`, with a `DetectionLimit` column.
- 6 groundwater results are between 0 and the DL (likely estimated / J-flagged values). `data_check.R` currently classifies these as non-detects.
- **DLs range from 0.01 to 0.5 µg/L** and have mostly dropped over time. This matters in two ways:
  1. Detection-frequency trends over time are confounded by the falling DLs.
  2. Many non-detects have a DL **above** a benchmark, so we can't say whether those samples exceed it. For example, 1,911 GW imidacloprid non-detects have DL > the 0.01 chronic benchmark / 0.02 preventive standard.

### Thresholds: `data/neonic_thresholds.csv` (ppb = µg/L; file has a UTF-8 BOM)
| Analyte | Aquatic acute | Aquatic chronic | Proposed enforcement (ES) | Proposed preventive (PAL) |
|---|---|---|---|---|
| Acetamiprid | 10.5 | 2.1 | – | – |
| Clothianidin | 11 | 0.05 | 1000 | 200 |
| Imidacloprid | 0.385 | 0.01 | 0.2 | 0.02 |
| Thiamethoxam | 17.5 | 0.74 | 120 | 12 |

Preliminary exceedance counts (detects ≥ benchmark / non-detects whose DL is above the benchmark):
- **GW imidacloprid:** acute 146 / 0 · chronic 718 / 1,911 · ES 319 / 226 · PAL 662 / 1,911
- **GW clothianidin:** chronic 855 / 1,406 (none exceed acute, ES or PAL)
- **GW thiamethoxam:** chronic 218 / 0 (none exceed acute, ES or PAL)
- **SW imidacloprid:** chronic 115 / 617 · ES 2 / 0 · PAL 68 / 617
- **SW clothianidin:** chronic 51 / 325
- **SW thiamethoxam:** chronic 1 / 0
- Acetamiprid: none

### Spatial layers: `shp/` (all WGS84 FlatGeobuf)
- `wi-county-bounds-24k.fgb`: 72 counties (`county_name`, `county_fips_code`, `dnr_region_name`). Note that `data_check.R` points at `shp/wi-counties.fgb`, which doesn't exist.
- `wi-dnr-watersheds.fgb` (334, `WSHED_CODE` / `WSHED_NAME`), `wi-huc-8-subbasins.fgb` (52), `wi-huc-10-watersheds.fgb` (372), `wi-huc-12-subwatersheds.fgb` (1,808).
- All site coordinates fall inside the WI bounding box, with no missing values.

---

## 2. Project structure (target)

```
Neonic Dashboard/
├── PLAN.md, SPEC.md
├── data/                  # raw CSVs + thresholds (gitignored for now)
├── shp/                   # raw boundary layers (gitignored for now)
├── data_check.R           # original exploration (kept for reference)
├── R/
│   └── prep_data.R        # Phase 1: raw → clean → app/data.RData
├── analysis.qmd           # Phase 2: loads app/data.RData, sources app/functions.R
└── app/                   # Phase 3: self-contained deployable bundle
    ├── functions.R        # shared analysis functions (used by both qmd and app)
    ├── data.RData         # built by R/prep_data.R (gitignored)
    ├── global.R, ui.R, server.R
    ├── src/               # numbered modules: 1.1__map.R, 2.1__summary.R, 2.2__timeseries.R …
    ├── md/                # about / methods copy
    └── www/               # styles.css, logos, favicon
```

`app/` holds everything the deployed app needs, so `rsconnect` can deploy that folder on its own (the same setup as the WAV Dashboard). `functions.R` lives in `app/`, and the qmd sources it from there, so the qmd and the app compute the numbers the same way.

---

## 3. Data decisions

Confirmed by Ben (2026-09-30): D1, D3, D5, D6, D8, and private-well blurring (D12). The rest are working defaults.

| # | Question | Decision |
|---|---|---|
| D1 | Detection rule | ✅ `detected = result > 0`. The 6 results between 0 and the DL count as detections and get an `estimated` flag. |
| D2 | Duplicates | Drop the 15 exact duplicate rows. The remaining conflicting keys are one well (VR882, 2022-05-11) sampled twice on one day, so keep both as separate samples (`sample_seq` 1/2). |
| D3 | Analytes in scope | ✅ Only imidacloprid, clothianidin, thiamethoxam and the combined total are selectable for visualization. Dinotefuran, acetamiprid and thiacloprid are described in the preamble and docs as "screened for, rarely or never detected". Site tooltips/popups list every analyte in that site's screen and mark which were not detected. |
| D4 | Combined total | Per sample event (site × date): the sum of detected concentrations across all analytes, with non-detects counted as 0. The event counts as detected if any analyte was. |
| D5 | Summary concentration statistic | ✅ Headline metric is detection frequency. Concentration stats use **detections only** (median / mean / max "of detections"), labeled that way everywhere. |
| D6 | Benchmark–water type pairing | ✅ Aquatic acute/chronic benchmarks ([EPA OPP Aquatic Life Benchmarks](https://www.epa.gov/pesticide-science-and-assessing-pesticide-risks/aquatic-life-benchmarks-and-ecological-risk)) are the primary comparison for **surface water**. Proposed ES/PAL (WI DNR NR 140 Cycle 13 review) are the primary comparison for **groundwater**. The qmd computes all 4 for both types; the app shows the relevant pair by default, with the others optional. |
| D7 | Exceedance accounting | For each sample × benchmark, sort the result into one of three groups: *exceeds* (detected and ≥ benchmark), *below* (detected < benchmark, or non-detect with DL ≤ benchmark), or *indeterminate* (non-detect with DL > benchmark). Report counts and % of samples, and also % of sites with ≥1 exceedance. |
| D8 | Watershed unit | ✅ **Counties and DNR watersheds** (`wi-dnr-watersheds.fgb`, 334 units). HUC layers are not used. |
| D9 | Groundwater well types | Include all well uses by default, with a filter. Summarize potable wells separately in the qmd, since the ES/PAL framing matters most there. |
| D10 | Time trends | Show annual detection frequency both raw and at a **common reporting level** (e.g. treat anything < 0.05 µg/L as ND), so trends aren't artifacts of falling DLs. The qmd will test which common level works. |
| D11 | Site-level summaries | Each site gets n samples, first/last date, n detects per analyte, max concentration, and exceedance flags, plus county, DNR watershed and well metadata. The spatial joins happen during prep, on the **true** coordinates. |
| D12 | Private well locations | ✅ Private (potable and non-potable) well coordinates are snapped to a 0.01° grid (~1 km) for display. If the snapped point lands in a different county or DNR watershed than the true location, it moves to the nearest point at least 50 m inside the correct county ∩ watershed polygon. That check runs against both the full-resolution and the simplified map layers. Result: 119 of 2,073 wells moved; display offset median 372 m, max 707 m; 172 display locations are shared by more than one well. True coordinates never go into the app data. Monitoring wells, piezometers and surface water stations keep their exact coordinates. |
| D13 | Private well IDs | WUWNs can be tied to well construction reports and addresses. So private wells get an anonymous public ID (`PW-####`) and a label like "Private well (Dane County)". The WUWN ↔ ID crosswalk is written to `data/` (gitignored) and kept out of the app data. |

---

## 4. Phase 1 — Data load & prep (`R/prep_data.R`)

Builds on `data_check.R`, keeping all raw → clean logic in one script.

**Status: done (2026-09-30).** Run `source("R/prep_data.R")` from the project root (~20 s).
- `result` is `NA` for non-detects (D1).
- `site_id` is the public ID: StationID for surface water, WUWN for monitoring wells and piezometers, `PW-####` for private wells.
- Plot with `map_lat` / `map_lon`. For private wells, `lat` / `lon` are `NA`.

- [x] Read both CSVs with explicit `col_types` (WUWN / StationID as character), `janitor::clean_names()`, and harmonize into one long table: `site_type` ("Surface water" / "Groundwater" factor), `site_id`, `date`, `year`, `month`, `sample_seq`, `analyte` (title-case factor), `featured`, `detected`, `estimated`, `result`, `dl`.
- [x] De-duplicate (D2) and build a `validation` list: dup counts, same-day repeats, results below the DL, DL by year, sites outside the WI polygons, blur stats.
- [x] Read the thresholds and pivot them long (`analyte`, `benchmark`, `value`, `label`, `short_label`, `primary_for`, `source`, `url`).
- [x] Build the `samples` table (one row per site × date × seq event) with the D4 combined total and an `any_detected` flag.
- [x] Build the `exceedances` table (result × benchmark → Exceeds / Below / Indeterminate, per D7).
- [x] Build the `sites` table: spatial join to county and DNR watershed (in WTM, EPSG:3071; one surface water station on the Mississippi River falls outside WI and gets the nearest polygon); GW well metadata; private-well blurring and anonymization (D12/D13); per-site summaries and exceedance counts (D11). Also build `site_analytes` (site × analyte screen) for popups.
- [x] Simplify polygons with `rmapshaper::ms_simplify()` for the app layers (counties and DNR watersheds).
- [x] Save `results`, `samples`, `sites`, `site_analytes`, `benchmarks`, `exceedances`, `validation`, `counties`, `watersheds` and `wi_state` to `app/data.RData` (0.73 MB, gitignored).
- [x] Fix the county file path in `data_check.R`.

## 5. Phase 2 — Analysis document (`analysis.qmd`)

A single self-contained HTML report in the WAV Quarto style (cosmo + Red Hat fonts, `code-fold`, `echo: false`, `freeze: auto`). Each section is a candidate app component.

1. **Data overview:** records, sites, date span, and analytes tested by water type. Sampling effort by year (bar chart) and by month (SW seasonality).
2. **Detection limits:** DL by analyte × year (heatmap / table), and why it matters for trends.
3. **Detection frequency:** by analyte × water type (grouped bars, the SPEC §6.2 teaser); annual trend raw vs. common reporting level (D10); % of sites ever detected.
4. **Concentrations:** detections-only distributions (log-scale box/jitter) by analyte × water type, with benchmark reference lines; top sites by max concentration.
5. **Benchmark exceedances** (the core request): for each water type × analyte × benchmark, a table (gt) of n samples, n / % exceeding, n indeterminate, n sites with any exceedance. A stacked-bar chart of exceeds / below / indeterminate. Exceedances over time. Plain-language notes on what each benchmark means.
6. **Groundwater context:** detection and exceedance by well use; well depth vs. detection (where depth exists).
7. **Geography:** county and watershed summaries (n sites, n samples, detection %, % samples > benchmark). Static ggplot choropleths with "no monitoring data" shown distinctly from 0%. An interactive `mapgl` map of sites colored by detection / exceedance status, with private wells at blurred locations.
8. **Combined total:** distribution and detection frequency of the D4 total, noting that it has no benchmark.
9. **Site profile prototype:** time series for 1–2 example sites (points = detects, open markers = NDs at the DL, benchmark lines), i.e. the app's site panel.
10. **Headline numbers:** the stat-card values for the app's intro page (SPEC §6.2).

Render: `quarto::quarto_render("analysis.qmd")`.

## 6. Phase 3 — Shiny app (`app/`)

WAV Dashboard architecture, with SPEC §6 content and §7 styling.

- **Framework:** `bslib::page_navbar` (Introduction / Explore / About) with a UW red navbar, a partner-link pre-header, a footer with attribution and last-updated date, and Red Hat Display/Text fonts. Design tokens from SPEC §7 go in `bs_theme()` + `www/styles.css`.
- **Map:** `mapgl` (MapLibre + Positron, same as the Quarto site) with `maplibre_proxy` for layer and filter updates. Layers: county choropleth, watershed choropleth, site circles, and a hatched gray "no data" fill. `leaflet` is the fallback if mapgl's Shiny interactivity comes up short.
- **Controls (Explore):** water type (tabs), analyte (imidacloprid / clothianidin / thiamethoxam / total), geography mode (county / DNR watershed / sites), map metric (detection % / median of detections / % exceeding benchmark), benchmark selector (disabled for total), GW well-use filter.
- **Right panel:** selection summary (statewide / county / watershed / site); plotly time series (log y, NDs as open markers at the DL, benchmark `hline`s); detection-by-analyte bars; exceedance summary table; site results table (DT) with CSV download.
- **Selection model:** click on map → `rv$selection`; a "Clear selection" chip returns to statewide. URL query params (`?type=&analyte=&geo=&sel=`) are restored on load, following the WAV `set_page_url()` pattern.
- **Modules (`src/`):** `1.1__controls.R`, `1.2__map.R`, `2.1__selection_summary.R`, `2.2__timeseries.R`, `2.3__analyte_bars.R`, `2.4__exceedances.R`, `3.1__intro.R`, `3.2__about.R`.
- **Performance:** everything aggregatable is precomputed in `prep_data.R`; the app only filters and summarizes small tables.
- **Deploy:** `rsconnect` to `connect.doit.wisc.edu`, same as the WAV Dashboard. Optionally add `renv` inside `app/`.

---

## 7. Open questions for Ben

1. ~~Confirm D1–D11~~ Done except D2, D7, D9, D10, D11, D13, which are proceeding as working defaults.
2. A URL for the NR 140 Cycle 13 proposed standards (the EPA benchmark URL is recorded).
3. ~~Which analytes are selectable~~ Done: the three featured analytes plus the total.
4. ~~Private well points~~ Done: blurred per D12.
5. Partner logos and URLs, and any required DATCP attribution language (carried over from SPEC §9).
