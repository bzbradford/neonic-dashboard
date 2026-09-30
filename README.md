# Neonicotinoids in Wisconsin Waters

An R Shiny dashboard for exploring neonicotinoid insecticide detections in Wisconsin surface water and groundwater. It uses monitoring data from the Wisconsin Department of Agriculture, Trade and Consumer Protection (DATCP) and was developed for outreach with UW–Madison Extension, Clean Wisconsin, and the River Alliance of Wisconsin.

**Live dashboard:** <https://connect.doit.wisc.edu/content/5099453e-d756-41b8-94ed-8a112659bd4c/>

The app has three pages:

- **About**: plain-language background, headline numbers for each water type, how to read the data, and the benchmarks used.
- **Summary**: the full exploratory analysis report (`analysis.qmd`), embedded in the app.
- **Explore**: an interactive map of counties, DNR watersheds, and monitoring sites. Choose a water type (surface, ground, or both), an analyte (imidacloprid, clothianidin, thiamethoxam, or any neonicotinoid), a map metric, a benchmark, and a year range. Selecting a place shows its summary stats, results over time, and a site table with a CSV download. Map views can be shared as URLs, e.g. `?water=Groundwater&sel=county:Portage`.

## Repository layout

```
├── R/
│   ├── prep_data.R     # raw data -> app/data.RData (cleaning, joins, privacy)
│   └── build.R         # runs prep, renders the report, copies it into the app
├── analysis.qmd        # exploratory analysis report (-> analysis.html)
├── analysis.css
├── app/                # self-contained Shiny app (this folder is what gets deployed)
│   ├── global.R        # packages, data, precomputed tables
│   ├── ui.R, server.R
│   ├── functions.R     # analysis helpers shared by the app and the report
│   ├── src/            # page modules: about, summary, explore (+ map data, charts)
│   └── www/            # styles.css, favicon/app icons, analysis.html (generated)
├── data_check.R        # original data exploration
├── PLAN.md             # project plan, data decisions (D1–D13), and findings
└── renv.lock
```

## Data

Raw data is **not** committed. To rebuild, place these files locally:

| Path | Contents |
|---|---|
| `data/neonic_data_groundwater.csv` | DATCP groundwater results (WUWN, coordinates, well metadata, date, analyte, result, detection limit) |
| `data/neonic_data_surfacewater.csv` | DATCP surface water results (StationID, name, coordinates, date, analyte, result, detection limit) |
| `data/neonic_thresholds.csv` | Benchmark values in ppb (µg/L) by analyte |
| `shp/wi-county-bounds-24k.fgb` | Wisconsin county boundaries |
| `shp/wi-dnr-watersheds.fgb` | Wisconsin DNR watershed boundaries |

Benchmarks:

- Aquatic life benchmarks (acute and chronic, freshwater invertebrates): [US EPA Office of Pesticide Programs](https://www.epa.gov/pesticide-science-and-assessing-pesticide-risks/aquatic-life-benchmarks-and-ecological-risk).
- Proposed groundwater enforcement standards and preventive action limits: [Wisconsin DNR NR 140, Cycle 13 review](https://dnr.wisconsin.gov/topic/Groundwater/NR140.html).

The generated files are also gitignored: `app/data.RData` (~0.7 MB) and `analysis.html` / `app/www/analysis.html` (~17 MB).

## Building and running

Requirements: R (the lockfile was built with R 4.6), the [Quarto CLI](https://quarto.org/), and the packages in `renv.lock`.

```r
renv::restore()          # install packages
source("R/build.R")      # data prep + report render + copy report into app/www
shiny::runApp("app")     # run the dashboard locally
```

`R/build.R` renders the report with the `quarto` command-line tool. If more than one version of R is installed, set `QUARTO_R` to the R you use with renv (for example, `Sys.setenv(QUARTO_R = "C:/Program Files/R/R-4.6.1/bin")`) so the report renders with the right package library.

To update the data, replace the CSVs in `data/`, run `source("R/build.R")`, check the validation messages it prints, and redeploy.

## Deployment

The app is deployed to Posit Connect (`connect.doit.wisc.edu`) from the `app/` folder with Posit Publisher; the configuration is in `app/.posit/publish/`. The deployed bundle must include `data.RData` and `www/analysis.html`. Both are gitignored, so run the build before publishing.

## Data handling

The full rationale is in [PLAN.md](PLAN.md) §3. In brief:

- **Detections.** A result above zero is a detection. Non-detects are never shown as zero; charts plot them at their detection limit.
- **Concentration statistics** (median, maximum) use detected results only.
- **Any neonicotinoid / combined total.** A sample counts as a detection if any analyte was detected. Its concentration is the sum of detected analytes, with non-detects counted as zero. There is no benchmark for the total.
- **Benchmark status.** Each result is *Exceeds*, *Below*, or *Indeterminate*. Indeterminate means a non-detect whose detection limit was above the benchmark, so it can't be classified. By default, surface water is compared to the EPA aquatic benchmarks and groundwater to the proposed NR 140 standards.
- **Water types.** Surface water and groundwater are summarized separately. The one exception is county and watershed colors in the Explore map's "Both" mode, where hover text breaks results out by water type.
- **Detection limits** fell from 0.2–0.5 µg/L (before 2015) to 0.01 µg/L (2019 on), so raw detection-frequency trends partly reflect better lab methods. The report compares trends at common reporting levels.

### Private well privacy

Private well locations are snapped to a ~1 km grid, adjusted so each point stays within its true county and DNR watershed. Private wells are identified only by anonymous IDs (`PW-####`). True coordinates and Wisconsin Unique Well Numbers never enter the app data or the report. The WUWN-to-ID crosswalk is written to `data/private_well_ids.csv`, which is gitignored.

## Accessibility

The dashboard targets WCAG 2.1 AA:

- **Contrast:** text meets 4.5:1 and map marks meet 3:1.
- **Color:** palettes stay distinguishable for common color-vision deficiencies, and status is never shown by color alone (legends, labels, and tooltips carry it too).
- **Keyboard:** focus is always visible. Everything the map does can be done with a keyboard, through the "Find a place" box and the site tables.
- **Screen readers:** selection changes are announced, and charts and report figures have text alternatives.
- **Motion:** map animations respect the reduced-motion setting.

Automated [axe-core](https://github.com/dequelabs/axe-core) checks pass except for two findings inside third-party table widgets: reactable places a live region inside its table body, and gt writes `headers` attributes.

## Credits

Dashboard by Ben Bradford, UW–Madison Entomology. Monitoring data: Wisconsin DATCP.
