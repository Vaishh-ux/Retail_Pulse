# RetailPulse feature audit

Every page, chart, table, control and download in the six-page Shiny app (commit `b73becd`) was inspected
against the project's purpose: help a small-shop owner understand sales, estimate demand hidden by stockouts,
see which products need attention, and show valid data-science evidence for the CSI3005 assessment.

**Actions:** KEEP = unchanged in purpose · SIMPLIFY = kept with fewer options or plainer wording ·
MERGE = combined with another feature · MOVE = kept, but under *Advanced details* · REMOVE = taken out of the UI
(the underlying R calculation is kept where it feeds another feature or the report).

"Load" is the measured or obvious cost on a small CPU: **H** = noticeable, **M** = some, **L** = negligible.

## Navigation and global controls

| Feature | What it does | Core? | Duplicates | Load | Action | Reason |
| --- | --- | --- | --- | --- | --- | --- |
| Six-page navbar | Overview, Product, Monitoring, Forecast & Scenarios, Data & Methods, Report | – | – | H (6 page servers per visit) | **MERGE → 3 pages** | Dashboard, Product Demand, Data & Model Results cover every core requirement |
| Store selector | Switches between stores 18, 235, 263 | Yes | – | L | **KEEP** | Real multi-store data; one control |
| Real/synthetic data label | Shows which data is loaded | Yes (honesty) | – | L | **KEEP** | Required so synthetic data is never mistaken for real |
| Global anomaly threshold (shared slider) | Changes \|z\| cut-off everywhere | No | – | M (recomputes rules) | **REMOVE control**, keep fixed 3.0 | Hard to explain; the sensitivity chart (kept) shows the effect |

## Overview (→ Dashboard)

| Feature | What it does | Core? | Duplicates | Load | Action | Reason |
| --- | --- | --- | --- | --- | --- | --- |
| Period selector | Last 7/14/28/56 days / whole period / custom | Yes | Date-range inputs | L | **SIMPLIFY** | Keep presets only |
| Custom date-range inputs | Pick exact dates | No | Period selector | L | **REMOVE** | Presets are enough and clearer |
| Category filter | Limit to one category | Useful | Category chart click | L | **KEEP** | Small shops think in categories |
| 6 KPI cards | Sales, demand, unmet share, stockout-hour rate, needs attention, forecast WAPE | Yes | WAPE repeats Data & Model Results | L | **SIMPLIFY → 4** | Sales, estimated demand, unmet demand, products needing attention; stockout-hour rate moves into the explanation, WAPE to the model page |
| Sales vs estimated demand chart | Daily totals with stockout bars | Yes | – | L | **KEEP** | The central idea of the project |
| Priority stock alerts panel | Top 6 replenish-earlier products | Yes | Action queue | L | **MERGE** into one attention list | Two lists of the same products |
| Action tiles + action queue | Counts per rule, filterable table | Yes | Alerts panel | M | **MERGE + SIMPLIFY** | One "Products that need attention" table with an action filter |
| Quick insights (5) | Plain-language findings | Yes | – | L | **SIMPLIFY → 3** | Kept as "What this means" |
| Top products chart | Top 12 by estimated demand | No | Attention list, product page | L | **REMOVE** | Doesn't say what to do |
| Category performance chart | Recorded vs unmet by category | Partly | Category filter | L | **MOVE** to Exploration | Useful analysis, not a daily decision |
| Product × day heatmap (3 modes) | Anomaly / demand / stockout grid | Academic (theory case-study Visualisation 2) | – | H (largest chart) | **MOVE** to Advanced details, one mode | Hard for non-experts; kept for the assessment |

## Product (→ Product Demand)

| Feature | What it does | Core? | Duplicates | Load | Action | Reason |
| --- | --- | --- | --- | --- | --- | --- |
| Product search/select | Choose a product | Yes | Find-a-product box | L | **KEEP** (one searchable select) | |
| Comparison product overlay | Second product's demand on the chart | No | Category comparison table | L | **REMOVE** | Overlapping lines confuse; category comparison kept |
| Forecast horizon slider 1–14 | Days to forecast | Yes | Scenario horizon | L | **SIMPLIFY** to 7 or 14 days | Only 7 days were evaluated; 14 shown with a warning |
| Show-forecast checkbox | Hide forecast | No | – | L | **REMOVE** | Forecast is the point of the page |
| Date range inputs | Zoom history | Partly | – | L | **SIMPLIFY** to "Show last 4 / 8 weeks / all" | |
| 5 product KPI cards | Sales, demand, unmet, stockout days, risk | Yes | Facts sidebar | L | **SIMPLIFY → 4** | |
| Sales/demand/forecast chart | History + forecast + stockout bars | Yes | – | M | **KEEP** | |
| Forecast explanation | Text under chart | Yes | – | L | **SIMPLIFY** into "What the forecast says" | Plain language, interval, reliability, caveat |
| Recommendation cards | Rule, evidence, if ignored | Yes | – | L | **KEEP** | Wording simplified; rule text in small print |
| Weekday × hour heatmap | When customers buy | Useful | Store version on model page | L | **MOVE** to "More about this product" | |
| Kaplan–Meier sell-out curve | Share of days still in stock by hour | Academic | Sell-out summary sentence | M | **SIMPLIFY** to one sentence + chart in "More about this product" | The statistic is useful; the curve needs explanation |
| In-stock vs out-of-stock bars (per product) | Censoring evidence | Academic | Store-level chart on model page | H (needs full hourly table, 12 MB) | **REMOVE** (store-level kept) | Same message, large memory cost |
| Category comparison table | Product vs category median | Useful | – | L | **MOVE** to "More about this product" | |
| Risk explanation | Why next-day risk is X% | Yes | – | L | **SIMPLIFY** to one sentence | |
| Facts sidebar | In-stock days, CV/hold-out WAPE, ETS form | Technical | – | L | **MOVE** to "More about this product" | |

## Monitoring (historical replay + alert explorer)

| Feature | What it does | Core? | Duplicates | Load | Action | Reason |
| --- | --- | --- | --- | --- | --- | --- |
| Hourly replay with play/pause/speed/reset/timeline/jump | Replays the evaluation week | No | – | H (timer re-renders every second; needs hourly replay table) | **REMOVE from UI** | Hard to explain, not a live feed, no decision value for a daily user |
| Replay alerts (pipeline) | Alerts raised hour by hour in the eval week | Partly | – | – | **KEEP calculation**, CSV download | Evidence that alerts use only past data |
| Alert explorer (type/severity/product/date filters, detail) | Browse alerts and anomalies | No | Attention list, anomalies CSV | M | **REMOVE** | Downloads cover it |

## Forecast & Scenarios

| Feature | What it does | Core? | Duplicates | Load | Action | Reason |
| --- | --- | --- | --- | --- | --- | --- |
| Scenario forecast chart + comparison tiles | What-if demand change / promotion | No | Product forecast | M (re-runs rules) | **REMOVE** | Hypothetical arithmetic; easy to misread as a prediction |
| Promotion-depth slider | Observational promotion multiplier | No | – | L | **REMOVE slider**, keep promotion-association table in Advanced | Not causal |
| Priority-weight sliders + rank table | Reweights the queue | No | – | M | **REMOVE** | Weights are documented in the rules section |
| Threshold sensitivity chart | Flags at each \|z\| | Academic | – | L | **MOVE** to Advanced details | Explains the anomaly cut-off without a control |

## Data & Methods (→ Data & Model Results)

| Feature | What it does | Core? | Duplicates | Load | Action | Reason |
| --- | --- | --- | --- | --- | --- | --- |
| Data-quality cards, raw vs cleaned, issues, missing values, features | Data preparation evidence | Yes | – | L | **KEEP** | Required by the brief |
| Before/after demand histogram | Effect of demand recovery | Yes | – | L | **KEEP** | |
| Store weekday × hour heatmap, in vs out of stock, variability scatter | EDA | Yes | – | L | **KEEP** (+ category chart moved here) | |
| Latent-demand validation (table, cut-off chart, scatter) | Validates estimated demand | Yes | – | M (5,587-point scatter) | **KEEP**, scatter under Advanced | |
| Forecast table, WAPE bars, actual vs forecast | Forecast evaluation | Yes | KPI WAPE | L | **KEEP** | |
| Risk metrics, confusion matrix, calibration, odds ratios | Stockout-risk evaluation | Yes | – | L | **KEEP** (calibration and odds ratios under Advanced) | |
| Decision rules text | R1–R6 thresholds | Yes | – | L | **MOVE** to Advanced details | |
| Dataset and limitations | Source, licence, limits | Yes | – | L | **KEEP** | |

## Report

| Feature | What it does | Core? | Duplicates | Load | Action | Reason |
| --- | --- | --- | --- | --- | --- | --- |
| Report page with preview iframe | Shows the R Markdown report | Yes | – | H (2.5 MB report loaded into an iframe) | **MERGE** into Data & Model Results → "Report & downloads"; no iframe | Opening it in a new tab is enough |
| Open / download report | R Markdown HTML per store | Yes | – | L | **KEEP** | |
| CSV downloads (recommendations, risk, replay alerts, anomalies, metrics) | Results files | Yes | – | L | **KEEP** | |

## Performance-related code (not visible features)

| Item | Finding | Action |
| --- | --- | --- |
| Results bundle compressed with xz | 0.61 s to read per store at full speed | gzip (0.07 s) |
| Full hourly table in the bundle | 11.7 of 19.3 MB per store in memory, used by one chart | Not loaded by the app any more |
| Rule engine built one tibble per recommendation | 0.76 s per run | Vectors, one table at the end: 0.12 s, identical output |
| Six page servers started per visitor | Every visit set up all pages | Three pages; Product and Model pages start when first opened |
| Static site (`site/`) | Separate JavaScript build added in `b73becd` | **REMOVE** — brief requires the R/Shiny app on the existing Render service |
