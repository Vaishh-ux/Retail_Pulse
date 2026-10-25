test_that("latent demand never falls below recorded sales and equals it on in-stock days", {
  d <- fixture()$d
  expect_true(all(d$latent >= d$sale_amount - 1e-9))
  expect_equal(d$latent[d$stock_h == 0], d$sale_amount[d$stock_h == 0])
  expect_true(all(d$latent_method[d$stock_h == 0] == "observed"))
})

test_that("latent demand recovers a known flat profile exactly", {
  cfg <- cfg_test()
  prof <- rep(0, 24); prof[7:22] <- 1 / 16
  rows <- lapply(0:13, function(k) make_row(1L, as.character(as.Date("2024-04-01") + k), 1.6 * prof, rep(0, 24)))
  st <- rep(0, 24); st[15:22] <- 1; h <- 1.6 * prof; h[15:22] <- 0      # out from 14:00, true total 1.6
  rows[[15]] <- make_row(1L, "2024-04-15", h, st)
  v <- rp_validate_and_clean(dplyr::bind_rows(rows), cfg)
  pf <- rp_fit_profiles(v$clean, v$H)
  d <- rp_latent_demand(v$clean, v$H, v$S, cfg, pf)
  expect_equal(d$latent[d$dt == as.Date("2024-04-15")], 1.6, tolerance = 1e-6)
})

test_that("latent-demand validation hides hours and beats observed-only totals", {
  f <- fixture(); tr <- f$d$split == "train"
  val <- rp_validate_latent(f$d[tr, ], f$v$H[tr, , drop = FALSE], f$cfg, f$pf)
  expect_gt(nrow(val$rows), 50)
  expect_true(all(val$rows$observed_only <= val$rows$actual + 1e-9))
  expect_lt(val$metrics["profile_method", "WAPE"], val$metrics["observed_only", "WAPE"])
})

test_that("forecast metrics are computed correctly", {
  m <- rp_metrics(c(2, 4), c(1, 5), lo = c(0, 3), hi = c(3, 6))
  expect_equal(m[["MAE"]], 1); expect_equal(m[["RMSE"]], 1)
  expect_equal(m[["WAPE"]], 2 / 6); expect_equal(m[["bias"]], 0); expect_equal(m[["coverage80"]], 1)
  e <- rp_metrics(numeric(0), numeric(0), numeric(0), numeric(0))
  expect_true(is.na(e[["WAPE"]]))                 # no in-stock days -> NA, not 0
})

test_that("forecasting produces evaluated, non-negative forecasts for every product", {
  skip_on_cran()
  f <- fixture(); cfg <- f$cfg
  d <- f$d[f$d$product_id %in% unique(f$d$product_id)[1:3], ]
  fc <- suppressWarnings(rp_forecast_all(d, cfg))
  expect_setequal(fc$cv_overall$.model, c("snaive", "ets"))
  expect_true(fc$chosen %in% c("snaive", "ets"))
  expect_true(all(fc$next_week$mean >= 0))
  expect_true(all(fc$next_week$lo80 <= fc$next_week$hi80))
  expect_equal(nrow(fc$next_week), 3 * 2 * cfg$horizon_max)
  # the evaluation forecasts lie strictly after the training data
  expect_true(min(fc$eval$dt) > max(d$dt[d$split == "train"]))
})

test_that("anomaly baseline uses only past in-stock days and flags an injected spike", {
  d <- fixture()$d
  pid <- min(d$product_id); i <- which(d$product_id == pid)[60]
  d2 <- d; d2$sale_amount[i] <- d2$sale_amount[i] * 8 + 5; d2$any_stockout[i] <- 0L
  s1 <- rp_anomaly_scores(d); s2 <- rp_anomaly_scores(d2)
  expect_equal(s1$reference[i], s2$reference[i])          # own value does not affect its baseline
  expect_gt(s2$z[i], 3)
  a <- rp_classify_anomalies(s2, 3)
  expect_true(any(a$product_id == pid & a$dt == d$dt[i] & a$direction == "surge"))
})

test_that("anomalies on stockout days are labelled as supply-side, not unexplained", {
  d <- fixture()$d
  x <- d[!is.na(d$z), ][1, ]; x$z <- -5; x$stock_h <- 10L; x$stockout_day <- 1L; x$promo <- 0L; x$holiday_flag <- 0L
  a <- rp_classify_anomalies(x, 3, rain_q = 999)
  expect_equal(a$cause, "Stockout (supply-side)")
  x$stock_h <- 0L; x$stockout_day <- 0L
  expect_equal(rp_classify_anomalies(x, 3, rain_q = 999)$cause, "Unexplained")
})

test_that("classification metrics are correct", {
  m <- rp_class_metrics(p = c(0.9, 0.8, 0.2, 0.1), y = c(1, 0, 1, 0), thr = 0.5)
  expect_equal(unname(m[c("TP", "FP", "FN", "TN")]), c(1, 1, 1, 1))
  expect_equal(m[["precision"]], 0.5); expect_equal(m[["recall"]], 0.5); expect_equal(m[["F1"]], 0.5)
  expect_equal(rp_auc(c(0.9, 0.1), c(1, 0)), 1)
})

test_that("risk model uses a chronological split with the threshold chosen on validation", {
  risk <- rp_fit_risk(fixture()$d)
  w <- risk$windows
  expect_true(w$fit[2] < w$validation[1]); expect_true(w$validation[2] < w$test[1])
  expect_true(risk$threshold > 0 && risk$threshold < 1)
  expect_true(all(c("logistic_test", "frequency_baseline_test") %in% rownames(risk$metrics)))
})
