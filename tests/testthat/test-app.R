# App-level checks against the real pipeline outputs in outputs/ (skipped if absent)
out_dir <- file.path(root, "outputs")
has_outputs <- file.exists(file.path(out_dir, "manifest.json"))
for (f in list.files(file.path(root, "app", "R"), pattern = "\\.R$", full.names = TRUE)) source(f)

test_that("pipeline outputs load and are internally consistent", {
  skip_if_not(has_outputs, "Run pipeline/run_pipeline.R first")
  RP <- rp_load_outputs(out_dir)
  expect_true(RP$ok)
  expect_true(RP$manifest$mode %in% c("real", "synthetic"))
  expect_equal(sort(unique(RP$daily$product_id)), sort(RP$products$product_id))
  expect_true(all(RP$recommendations$product_id %in% RP$products$product_id))
  expect_true(all(RP$daily$latent >= RP$daily$sale_amount - 1e-9))
  expect_true(all(c("ets", "snaive") %in% RP$forecast_eval_overall$.model))
})

test_that("missing outputs are reported instead of crashing", {
  r <- rp_load_outputs(tempfile("nothing_here"))
  expect_false(r$ok); expect_true("manifest.json" %in% r$missing)
})

test_that("every chart builder handles empty input", {
  e <- tibble::tibble()
  for (fn in list(ch_trend, ch_store_trend, ch_weekday_hour, ch_instock_vs_out, ch_sellout, ch_actual_vs_fc,
                  ch_latent_scatter, ch_latent_cutoff, ch_calibration, ch_variability))
    expect_s3_class(fn(e), "plotly")
  expect_s3_class(ch_heatmap(e, c()), "plotly")
  expect_s3_class(ch_categories(e), "plotly")
})

test_that("chart builders render real outputs to valid widgets", {
  skip_if_not(has_outputs)
  RP <- rp_load_outputs(out_dir)
  pid <- RP$products$product_id[1]
  ws <- list(
    ch_trend(RP$daily[RP$daily$product_id == pid, ], RP$anomalies[RP$anomalies$product_id == pid, ],
             RP$forecast_next[RP$forecast_next$product_id == pid & RP$forecast_next$.model == "ets", ], 14),
    ch_heatmap(RP$daily, RP$label_of), ch_heatmap(RP$daily, RP$label_of, mode = "demand"), ch_heatmap(RP$daily, RP$label_of, mode = "stockout"),
    ch_store_trend(RP$store_daily),
    ch_model_bars(RP$forecast_cv_overall, RP$forecast_eval_overall), ch_coefs(RP$risk_coefficients))
  for (w in ws) {
    f <- tempfile(fileext = ".html")
    expect_silent(suppressMessages(htmlwidgets::saveWidget(w, f, selfcontained = FALSE)))
    expect_true(file.exists(f))
  }
})

test_that("the Shiny app object builds and exposes the three pages", {
  skip_if_not(has_outputs)
  old <- setwd(file.path(root, "app")); on.exit(setwd(old))
  Sys.setenv(RP_ROOT = root)
  app <- shiny::shinyAppDir(".")
  expect_s3_class(app, "shiny.appobj")
  ui_txt <- paste(readLines(file.path(root, "app", "app.R")), collapse = "\n")
  for (p in c("dashboard", "product", "results")) expect_match(ui_txt, sprintf('value = "%s"', p))
  for (gone in c("overview", "monitor", "scenario", "methods")) expect_no_match(ui_txt, sprintf("value = \"%s\"", gone))
})

test_that("Models-page charts build without size errors", {
  skip_if_not(has_outputs)
  RP <- rp_load_outputs(out_dir)
  for (w in list(ch_calibration(RP$risk_calibration), ch_latent_scatter(RP$latent_validation_rows),
                 ch_latent_cutoff(RP$latent_validation_by_cutoff), ch_variability(RP$variability),
                 ch_actual_vs_fc(RP$forecast_eval[RP$forecast_eval$product_id == RP$products$product_id[1], ])))
    expect_silent(plotly::plotly_build(w))
})

test_that("store registry finds every shipped store and falls back to the default", {
  skip_if_not(has_outputs)
  dirs <- rp_store_dirs(out_dir)
  expect_true(length(dirs) >= 1)
  expect_false(any(duplicated(names(dirs))))
  def <- rp_get_store(dirs, "not-a-store")
  expect_equal(as.character(def$manifest$store_id), names(dirs)[1])
  for (sid in names(dirs)) {
    RP <- rp_get_store(dirs, sid)
    expect_true(RP$ok)
    expect_equal(as.character(RP$manifest$store_id), sid)
    expect_equal(RP$manifest$mode, rp_get_store(dirs, names(dirs)[1])$manifest$mode)  # never mix real and synthetic stores
  }
  expect_length(rp_store_dirs(tempfile("none")), 0)
})

test_that("scenario growth changes the forecast ratio used by the surge/decline rules", {
  skip_if_not(has_outputs)
  RP <- rp_load_outputs(out_dir)
  an <- rp_classify_anomalies(RP$daily, 3, stats::quantile(RP$daily$precpt, 0.9, na.rm = TRUE))
  ind <- function(g) rp_product_indicators(RP$daily, RP$forecast_next, RP$manifest$chosen_model, an, RP$risk_next,
                                          RP$forecast_cv_product, RP$products, growth = g)
  a <- ind(1); b <- ind(1.5)
  expect_equal(b$fc_ratio, a$fc_ratio * 1.5, tolerance = 1e-9)
  ra <- rp_recommend(a, risk_threshold = RP$manifest$risk_threshold); rb <- rp_recommend(b, risk_threshold = RP$manifest$risk_threshold)
  expect_gte(sum(rb$action == "Review possible demand surge"), sum(ra$action == "Review possible demand surge"))
})

test_that("app bundles are lean, gzip-compressed and complete for the three pages", {
  skip_if_not(has_outputs)
  for (d in rp_store_dirs(out_dir)) {
    f <- file.path(d, "app_bundle.rds")
    expect_true(file.exists(f))
    expect_identical(readBin(f, "raw", 2), as.raw(c(0x1f, 0x8b)))           # gzip magic bytes
    b <- readRDS(f)
    expect_false(any(c("hourly", "replay") %in% names(b)))                     # large tables not loaded by the app
    for (n in c("daily", "products", "forecast_next", "recommendations", "risk_metrics", "alerts", "weekday_hour", "sellout_curves"))
      expect_true(n %in% names(b), info = n)
    expect_lt(as.numeric(object.size(b)) / 1e6, 10)
  }
})

test_that("faster rule engine gives exactly the pipeline's recommendations", {
  skip_if_not(has_outputs)
  RP <- rp_load_outputs(out_dir)
  an <- rp_classify_anomalies(RP$daily, RP$manifest$thresholds$anomaly_z, stats::quantile(RP$daily$precpt, 0.9, na.rm = TRUE))
  ind <- rp_product_indicators(RP$daily, RP$forecast_next, RP$manifest$chosen_model, an, RP$risk_next, RP$forecast_cv_product, RP$products)
  r <- rp_recommend(ind, list(), RP$manifest$risk_threshold)
  cols <- c("product_id", "action", "urgency", "reliability", "priority", "rule", "reason", "evidence")
  expect_equal(as.data.frame(r[, cols]), as.data.frame(RP$recommendations[, cols]), ignore_attr = TRUE)
})
