# Export the R pipeline's results as compact JSON for the static dashboard (site/).
# All analysis stays in R: this script only reshapes outputs/ (and outputs/stores/<id>/)
# into one JSON file per store, plus copies the knitted R Markdown reports.
#
#   Rscript scripts/export_static.R            # after pipeline/run_pipeline.R and scripts/knit_reports.R
#
# Tables are written column-wise ({"col": [values...]}) to keep files small.

suppressPackageStartupMessages({ library(jsonlite) })
root <- normalizePath(Sys.getenv("RP_ROOT", unset = "."))
source(file.path(root, "R", "config.R")); source(file.path(root, "R", "decide.R"))
for (f in list.files(file.path(root, "app", "R"), pattern = "^00_data\\.R$", full.names = TRUE)) source(f)
out <- file.path(root, "outputs")
site <- file.path(root, "site")
dir.create(file.path(site, "data"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(site, "reports"), recursive = TRUE, showWarnings = FALSE)

cols <- function(df, digits = 7) {
  df <- as.data.frame(df)
  for (n in names(df)) {
    x <- df[[n]]
    if (inherits(x, "Date")) df[[n]] <- format(x, "%Y-%m-%d")
    else if (inherits(x, "POSIXt")) df[[n]] <- format(x, "%Y-%m-%d %H:%M")
    else if (is.double(x)) df[[n]] <- if (n == "z") ifelse(is.na(x), NA, sprintf("%.17g", x)) else signif(round(x, 6), digits)  # z as exact text: threshold comparisons must match R
    else if (is.logical(x)) df[[n]] <- as.integer(x)
    else if (is.factor(x)) df[[n]] <- as.character(x)
  }
  as.list(df)
}

dirs <- rp_store_dirs(out)
index <- list()
for (sid in names(dirs)) {
  RP <- rp_load_outputs(dirs[[sid]])
  stopifnot(isTRUE(RP$ok))
  m <- RP$manifest
  d <- RP$daily[order(RP$daily$product_id, RP$daily$dt), ]
  # per-product mean sales per trading hour, in stock vs out of stock (Product page)
  h <- RP$hourly[RP$hourly$hour %in% 6:21, ]
  io <- stats::aggregate(sales ~ product_id + hour + out, h, mean)
  names(io)[names(io) == "sales"] <- "mean_sales"
  fe <- RP$forecast_eval[RP$forecast_eval$.model %in% c("ets", "snaive"), ]
  rec <- RP$recommendations
  data <- list(
    manifest = m, quality = RP$quality, latent_val = RP$latent_val,
    rain_q = unname(stats::quantile(d$precpt, 0.9, na.rm = TRUE)),
    rules = RP_RULE_DEFAULTS,
    daily = cols(d[, c("product_id", "first_category_id", "dt", "split", "weekday", "sale_amount", "latent", "lost", "latent_method",
                       "stock_h", "any_stockout", "stockout_day", "event", "promo", "promo_depth", "holiday_flag", "precpt",
                       "reference", "z")]),
    store_daily = cols(RP$store_daily),
    products = cols(RP$products[, c("product_id", "label", "category", "first_category_id", "days", "zero_sale_share", "stockout_hour_rate",
                                    "full_instock_days", "promo_days", "mean_latent", "cv", "unmet_share", "sellout_days", "sellout_share",
                                    "median_sellout_hour", "p_instock_18", "risk")]),
    forecast_next = cols(RP$forecast_next[RP$forecast_next$.model == m$chosen_model, c("product_id", "dt", "mean", "lo80", "hi80")]),
    forecast_eval = cols(fe[, c("product_id", ".model", "dt", "mean", "sale_amount", "any_stockout")]),
    forecast_cv_overall = cols(RP$forecast_cv_overall), forecast_eval_overall = cols(RP$forecast_eval_overall),
    forecast_cv_product = cols(RP$forecast_cv_product[, c("product_id", ".model", "WAPE")]),
    forecast_eval_product = cols(RP$forecast_eval_product[, c("product_id", ".model", "WAPE")]),
    ets_spec = cols(RP$ets_spec),
    weekday_hour = cols(RP$weekday_hour[, c("product_id", "weekday", "hour", "mean_sales")]),
    store_weekday_hour = cols(RP$store_weekday_hour),
    instock_out = cols(io), instock_vs_out = cols(RP$instock_vs_out),
    sellout_curves = cols(RP$sellout_curves),
    replay = cols(RP$replay[, c("product_id", "dt", "hour", "out", "cum_obs", "cum_exp", "cum_lo", "cum_hi")]),
    alerts = cols(RP$alerts[, c("product_id", "dt", "hour", "severity", "type", "message", "observed", "expected")]),
    risk_next = cols(RP$risk_next[, c("product_id", "so_rate7", "so_hours7", "yest_event", "demand_ratio", "next_dt", "promo", "holiday_flag", "weekend", "risk")]),
    risk_metrics = cols(RP$risk_metrics), risk_coefficients = cols(RP$risk_coefficients), risk_calibration = cols(RP$risk_calibration),
    promo_effects = cols(RP$promo_effects[, c("first_category_id", "n_promo_days", "beta", "se")]),
    variability = cols(RP$variability), feature_dictionary = cols(RP$feature_dictionary),
    latent_validation_by_cutoff = cols(RP$latent_validation_by_cutoff),
    latent_validation_rows = cols(RP$latent_validation_rows[, c("actual", "observed_only", "estimate")], 3),
    # R's own default recommendations: the browser recomputes them and the tests check both agree
    anomalies_n_r = nrow(RP$anomalies),
    recommendations_r = cols(rec[, c("product_id", "action", "urgency", "reliability", "priority", "rule")])
  )
  f <- file.path(site, "data", sprintf("store_%s.json", sid))
  jsonlite::write_json(data, f, auto_unbox = TRUE, na = "null", digits = NA)
  rep_src <- file.path(root, "app", "www", "reports", sprintf("report_%s.html", sid))
  if (file.exists(rep_src)) file.copy(rep_src, file.path(site, "reports", basename(rep_src)), overwrite = TRUE)
  index[[length(index) + 1]] <- list(store_id = m$store_id, products = m$products, mode = m$mode,
                                     file = basename(f), report = if (file.exists(rep_src)) file.path("reports", basename(rep_src)) else NULL)
  message(sprintf("store %s -> %s (%.1f MB)", sid, f, file.size(f) / 1e6))
}
jsonlite::write_json(list(stores = index, default = index[[1]]$store_id, generated = format(Sys.time(), "%Y-%m-%d %H:%M")),
                     file.path(site, "data", "index.json"), auto_unbox = TRUE, pretty = TRUE)
message("index written")
