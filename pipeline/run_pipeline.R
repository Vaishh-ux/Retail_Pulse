#!/usr/bin/env Rscript
# RetailPulse analytical pipeline ------------------------------------------------
# Usage:  Rscript pipeline/run_pipeline.R
# Reads one store of FreshRetailNet-50K (or synthetic demo data if the real files
# are unavailable), runs every analysis step and writes results to outputs/.
# The Shiny app and the report only READ these outputs.

suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(arrow)
})
root <- Sys.getenv("RP_ROOT", unset = normalizePath(file.path(dirname(sub("--file=", "", grep("--file=", commandArgs(FALSE), value = TRUE)[1])), "..")))
Sys.setenv(RP_ROOT = root)
for (f in list.files(file.path(root, "R"), pattern = "\\.R$", full.names = TRUE)) source(f)

cfg <- rp_config()
set.seed(cfg$seed)
dir.create(cfg$out_dir, recursive = TRUE, showWarnings = FALSE)
t_start <- Sys.time()
log_step <- function(...) message(sprintf("[%s] %s", format(Sys.time(), "%H:%M:%S"), paste0(...)))
w_parquet <- function(x, name) arrow::write_parquet(x, file.path(cfg$out_dir, paste0(name, ".parquet")))
w_json <- function(x, name) jsonlite::write_json(x, file.path(cfg$out_dir, paste0(name, ".json")),
                                                 auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null")

# 1. Load ---------------------------------------------------------------------
mode <- rp_resolve_mode(cfg)
log_step("data mode: ", mode)
ld <- rp_load_store(cfg, mode)
raw <- ld$data
log_step("store ", ld$store_id, ": ", nrow(raw), " raw rows")
raw_profile <- list(
  rows = nrow(raw), columns = ncol(raw) - 1L,
  rows_by_split = as.list(table(raw$split)),
  products = length(unique(raw$product_id)),
  date_min = min(raw$dt), date_max = max(raw$dt),
  missing_by_column = as.list(vapply(raw[setdiff(RP_SCHEMA, c("hours_sale", "hours_stock_status"))], function(x) sum(is.na(x)), 0L)),
  sale_amount_summary = as.list(stats::quantile(raw$sale_amount, c(0, .25, .5, .75, .95, 1), na.rm = TRUE))
)
if (!is.null(ld$store_summary)) w_parquet(ld$store_summary, "store_summary")

# 2. Validate and clean ---------------------------------------------------------
v <- rp_validate_and_clean(raw, cfg)
d <- v$clean; H <- v$H; S <- v$S
log_step("clean rows: ", nrow(d), "; duplicates removed: ", v$report$duplicates_removed,
         "; hourly/daily mismatches repaired: ", v$report$hourly_daily_mismatch)

# 3. Stockout-aware demand (profiles fitted on TRAINING days only) ---------------
tr <- d$split == "train"
pf <- rp_fit_profiles(d[tr, ], H[tr, , drop = FALSE])
d <- rp_latent_demand(d, H, S, cfg, pf)
val <- rp_validate_latent(d[tr, ], H[tr, , drop = FALSE], cfg, pf, seed = cfg$seed)
log_step("latent demand: ", sum(d$latent_method != "observed"), " stockout days adjusted; validation n = ", nrow(val$rows))

# 4. Features ---------------------------------------------------------------------
d <- rp_add_features(d, cfg$risk_event_h)

# 5. Forecasts ----------------------------------------------------------------------
log_step("forecasting (rolling-origin CV + hold-out) ...")
fc <- suppressWarnings(rp_forecast_all(d, cfg))
log_step("chosen model by CV WAPE: ", fc$chosen)

# 6. Anomalies ---------------------------------------------------------------------
d <- rp_anomaly_scores(d)
rain_q <- stats::quantile(d$precpt, 0.9, na.rm = TRUE)
anoms <- rp_classify_anomalies(d, cfg$anomaly_z, rain_q)
runs <- rp_sustained_runs(d)
log_step("anomalies flagged: ", nrow(anoms))

# 7. Stockout risk -----------------------------------------------------------------
risk <- rp_fit_risk(d)
risk_next <- rp_risk_next(d, risk)
log_step("risk model threshold: ", risk$threshold)

# 8. Sell-out timing -------------------------------------------------------------
so_times <- rp_sellout_times(d, S, cfg)
so_curves <- rp_sellout_curves(so_times)
so_summary <- rp_sellout_summary(so_times)

# 9. Simulated replay ------------------------------------------------------------
fc_eval_chosen <- fc$eval[fc$eval$.model == fc$chosen, ]
replay <- rp_replay_table(d, H, S, pf, fc_eval_chosen, cfg)
alerts <- rp_replay_alerts(replay, cfg)

# 10. Scenario support -------------------------------------------------------------
promo <- rp_promo_effects(d)

# 11. Decisions --------------------------------------------------------------------
ind <- rp_product_indicators(d, fc$next_week, fc$chosen, anoms, risk_next, fc$cv_product, v$per_product)
recs <- rp_recommend(ind, risk_threshold = risk$threshold)

# 12. Exploratory tables -----------------------------------------------------------
hourly <- tibble::tibble(product_id = rep(d$product_id, each = 24), dt = rep(d$dt, each = 24),
                         weekday = rep(d$weekday, each = 24), hour = rep(0:23, nrow(d)),
                         sales = as.vector(t(H)), out = as.integer(as.vector(t(S))))
wd_hour <- hourly |>
  dplyr::filter(out == 0L) |>
  dplyr::group_by(product_id, weekday, hour) |>
  dplyr::summarise(mean_sales = mean(sales), n = dplyr::n(), .groups = "drop")
store_wd_hour <- hourly |>
  dplyr::filter(out == 0L) |>
  dplyr::group_by(weekday, hour) |>
  dplyr::summarise(mean_sales = mean(sales), .groups = "drop")
instock_vs_out <- hourly |>
  dplyr::filter(hour %in% 6:21) |>
  dplyr::group_by(hour, status = ifelse(out == 1L, "Out of stock", "In stock")) |>
  dplyr::summarise(mean_sales = mean(sales), hours = dplyr::n(), .groups = "drop")
variability <- d |>
  dplyr::group_by(product_id, first_category_id) |>
  dplyr::summarise(mean_latent = mean(latent), sd_latent = stats::sd(latent),
                   cv = sd_latent / pmax(mean_latent, 1e-6), mean_obs = mean(sale_amount),
                   unmet_share = sum(latent - sale_amount) / pmax(sum(latent), 1e-6), .groups = "drop")
store_daily <- d |>
  dplyr::group_by(dt, split) |>
  dplyr::summarise(observed = sum(sale_amount), latent = sum(latent), stockout_hours = sum(stock_h),
                   products_out = sum(any_stockout), promo_products = sum(promo), holiday = max(holiday_flag),
                   precpt = mean(precpt), .groups = "drop")

products <- d |>
  dplyr::distinct(product_id, first_category_id, second_category_id, third_category_id) |>
  dplyr::left_join(v$per_product, by = "product_id") |>
  dplyr::left_join(variability |> dplyr::select(-first_category_id), by = "product_id") |>
  dplyr::left_join(so_summary, by = "product_id", suffix = c("", "_so")) |>
  dplyr::left_join(risk_next[, c("product_id", "risk", "risk_flag")], by = "product_id") |>
  dplyr::mutate(label = paste0("P", product_id), category = paste0("Category ", first_category_id))

feature_dictionary <- tibble::tribble(
  ~feature, ~definition, ~uses_future,
  "weekday / weekend", "Day of week from dt (1 = Monday); weekend = Saturday or Sunday", "No",
  "promo, promo_depth", "promo = discount < 1 or activity_flag = 1; depth = 1 - discount", "Same-day planned flag",
  "stock_h", "Out-of-stock hours between 06:00 and 21:59, recomputed from hours_stock_status", "No (same day, descriptive)",
  "latent", "Estimated demand: recorded sales + estimated unmet demand in out-of-stock hours", "Profile fitted on training days only",
  "lag1, lag7", "Estimated demand 1 and 7 days earlier", "No",
  "roll7, roll28", "Mean estimated demand over the previous 7 / 28 days (excludes day t)", "No",
  "so_rate7, so_hours7", "Share of the previous 7 days with >= 4 stockout hours; mean stockout hours", "No",
  "yest_event", "Risk event on the previous day", "No",
  "hist_freq", "Expanding event frequency up to day t-1", "No",
  "demand_ratio", "roll7 / roll28 (recent change in demand)", "No",
  "z", "Robust z-score vs the previous 28 in-stock days", "No"
)

# 13. Write outputs ------------------------------------------------------------------
w_parquet(d |> dplyr::select(product_id, first_category_id, dt, split, weekday, weektype, sale_amount, sale_amount_reported,
                             latent, lost, latent_method, share_in_stock, stock_h, any_stockout, stockout_day, event,
                             discount, promo, promo_depth, holiday_flag, activity_flag, precpt, avg_temperature,
                             reference, spread, z, wd_factor, roll7, roll28, demand_ratio), "daily")
w_parquet(hourly, "hourly")
w_parquet(wd_hour, "weekday_hour")
w_parquet(store_wd_hour, "store_weekday_hour")
w_parquet(instock_vs_out, "instock_vs_out")
w_parquet(variability, "variability")
w_parquet(store_daily, "store_daily")
w_parquet(products, "products")
w_parquet(val$rows, "latent_validation_rows")
w_parquet(val$by_cutoff, "latent_validation_by_cutoff")
w_parquet(fc$cv, "forecast_cv")
w_parquet(fc$cv_overall, "forecast_cv_overall")
w_parquet(fc$cv_product, "forecast_cv_product")
w_parquet(fc$eval, "forecast_eval")
w_parquet(fc$eval_overall, "forecast_eval_overall")
w_parquet(fc$eval_product, "forecast_eval_product")
w_parquet(fc$next_week, "forecast_next")
w_parquet(fc$ets_spec, "ets_spec")
w_parquet(anoms, "anomalies")
w_parquet(runs, "sustained_runs")
w_parquet(risk$coefs, "risk_coefficients")
w_parquet(risk$calibration, "risk_calibration")
w_parquet(tibble::as_tibble(risk$metrics, rownames = "set"), "risk_metrics")
w_parquet(risk_next, "risk_next")
w_parquet(so_curves, "sellout_curves")
w_parquet(so_summary, "sellout_summary")
w_parquet(replay, "replay")
w_parquet(alerts, "alerts")
w_parquet(promo, "promo_effects")
w_parquet(ind, "indicators")
w_parquet(recs, "recommendations")
w_parquet(feature_dictionary, "feature_dictionary")

quality <- v$report
quality$raw_profile <- raw_profile
w_json(quality, "quality")
w_json(list(metrics = tibble::as_tibble(val$metrics, rownames = "method"), n = nrow(val$rows)), "latent_validation")

manifest <- list(
  project = "RetailPulse",
  mode = mode,
  mode_note = if (mode == "synthetic") "SYNTHETIC DEMO DATA - illustrative only, not FreshRetailNet-50K findings" else "FreshRetailNet-50K (Dingdong-Inc, CC BY 4.0)",
  store_id = ld$store_id,
  products = length(unique(d$product_id)),
  date_min = format(min(d$dt)), date_max = format(max(d$dt)),
  train_range = format(range(d$dt[d$split == "train"])), eval_range = format(range(d$dt[d$split == "eval"])),
  chosen_model = fc$chosen, cv_origins = fc$origins, evaluated_horizon = fc$evaluated_h, horizon_max = cfg$horizon_max,
  risk_threshold = risk$threshold, risk_windows = lapply(risk$windows, format), risk_class_balance = as.list(risk$class_balance),
  thresholds = list(stockout_day_hours = cfg$stockout_day_h, risk_event_hours = cfg$risk_event_h,
                    anomaly_z = cfg$anomaly_z, baseline_window = cfg$baseline_window, min_share_in = cfg$min_share_in),
  rules = RP_RULE_DEFAULTS[setdiff(names(RP_RULE_DEFAULTS), "risk_thr")],
  generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
  runtime_seconds = round(as.numeric(difftime(Sys.time(), t_start, units = "secs")), 1),
  r_version = R.version.string,
  packages = as.list(vapply(c("dplyr", "arrow", "fable", "fabletools", "survival", "slider"), function(p) as.character(utils::packageVersion(p)), ""))
)
w_json(manifest, "manifest")

# One compact bundle for the web app (see R/bundle.R)
rp_write_bundle(cfg$out_dir)
log_step("done in ", manifest$runtime_seconds, " s -> ", cfg$out_dir)
