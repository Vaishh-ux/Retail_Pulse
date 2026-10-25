# Forecasting: seasonal-naive baseline vs ETS, on latent daily demand ----------
# Evaluation:
#   1. Rolling-origin cross-validation inside the training period (4 origins, h = 7).
#   2. Final hold-out test on the dataset's evaluation split (the 7 days after
#      training). Scored ONLY on in-stock days (no trading-hour stockout), where
#      recorded sales equal demand; also reported against latent demand.

RP_MODELS <- c("snaive", "ets")

rp_fit_models <- function(ts) {
  ts |>
    fabletools::model(
      snaive = fable::SNAIVE(latent ~ lag("week")),
      ets = fable::ETS(latent)
    )
}

rp_hilo_cols <- function(fc, level = 80) {
  hl <- fabletools::hilo(fc$latent, level)
  fc$lo80 <- pmax(0, hl$lower); fc$hi80 <- pmax(0, hl$upper)
  hl95 <- fabletools::hilo(fc$latent, 95)
  fc$lo95 <- pmax(0, hl95$lower); fc$hi95 <- pmax(0, hl95$upper)
  fc$mean <- pmax(0, fc$.mean)
  tibble::as_tibble(fc) |> dplyr::select(product_id, .model, dt, mean, lo80, hi80, lo95, hi95)
}

rp_metrics <- function(f, a, lo = NULL, hi = NULL) {
  ok <- !is.na(f) & !is.na(a)
  f <- f[ok]; a <- a[ok]
  if (!length(a)) return(c(n = 0, MAE = NA, RMSE = NA, WAPE = NA, bias = NA, coverage80 = if (!is.null(lo)) NA))
  out <- c(n = length(a), MAE = mean(abs(f - a)), RMSE = sqrt(mean((f - a)^2)), WAPE = sum(abs(f - a)) / max(sum(a), 1e-9),
           bias = sum(f - a) / max(sum(a), 1e-9))
  if (!is.null(lo)) out <- c(out, coverage80 = mean(a >= lo[ok] & a <= hi[ok]))
  out
}

rp_forecast_all <- function(d, cfg) {
  h <- cfg$horizon
  train <- d[d$split == "train", c("product_id", "dt", "latent")]
  ts_train <- tsibble::as_tsibble(train, key = product_id, index = dt)

  # 1) rolling-origin CV on the training period
  n_days <- length(unique(train$dt))
  origins <- seq(n_days - 4 * h, n_days - h, by = h)
  cv <- lapply(origins, function(o) {
    cut <- sort(unique(train$dt))[o]
    fit <- rp_fit_models(ts_train |> dplyr::filter(dt <= cut))
    fc <- rp_hilo_cols(fabletools::forecast(fit, h = h))
    fc$origin <- cut
    fc
  })
  cv <- dplyr::bind_rows(cv) |>
    dplyr::left_join(d[, c("product_id", "dt", "sale_amount", "latent", "any_stockout")], by = c("product_id", "dt"))

  # 2) fit on the full training period, forecast the evaluation week
  fit_train <- rp_fit_models(ts_train)
  fc_eval <- rp_hilo_cols(fabletools::forecast(fit_train, h = h)) |>
    dplyr::left_join(d[d$split == "eval", c("product_id", "dt", "sale_amount", "latent", "any_stockout", "stock_h")],
                     by = c("product_id", "dt"))
  ets_spec <- tibble::tibble(product_id = fit_train$product_id,
                             ets_form = vapply(fit_train$ets, function(m) tryCatch(format(m), error = function(e) "ETS"), ""))

  metric_tbl <- function(x, by) {
    x |>
      dplyr::group_by(dplyr::across(dplyr::all_of(by))) |>
      dplyr::group_modify(function(g, k) {
        ins <- g[g$any_stockout == 0, ]
        a <- rp_metrics(ins$mean, ins$sale_amount, ins$lo80, ins$hi80)
        b <- rp_metrics(g$mean, g$latent, g$lo80, g$hi80)
        tibble::tibble(n_instock = a[["n"]], MAE = a[["MAE"]], RMSE = a[["RMSE"]], WAPE = a[["WAPE"]], bias = a[["bias"]],
                       coverage80 = a[["coverage80"]],
                       WAPE_vs_latent = b[["WAPE"]], coverage80_vs_latent = b[["coverage80"]])
      }) |>
      dplyr::ungroup()
  }
  cv_overall <- metric_tbl(cv, ".model")
  cv_product <- metric_tbl(cv, c("product_id", ".model"))
  eval_overall <- metric_tbl(fc_eval, ".model")
  eval_product <- metric_tbl(fc_eval, c("product_id", ".model"))

  # model choice: lower cross-validated WAPE overall (decided on training data only)
  chosen <- cv_overall$.model[which.min(cv_overall$WAPE)]

  # 3) production forecast: refit on all available days, forecast beyond the data
  ts_all <- tsibble::as_tsibble(d[, c("product_id", "dt", "latent")], key = product_id, index = dt)
  fit_all <- rp_fit_models(ts_all)
  fc_next <- rp_hilo_cols(fabletools::forecast(fit_all, h = cfg$horizon_max))

  list(cv = cv, cv_overall = cv_overall, cv_product = cv_product,
       eval = fc_eval, eval_overall = eval_overall, eval_product = eval_product,
       chosen = chosen, next_week = fc_next, evaluated_h = h, ets_spec = ets_spec, origins = as.character(sort(unique(train$dt))[origins]))
}
