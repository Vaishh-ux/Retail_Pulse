# Stockout-risk model -----------------------------------------------------------
# Target  : event_t = 1 if the product is out of stock for >= RP_RISK_EVENT_HOURS
#           of the 16 trading hours on day t (dataset field hours_stock_status).
# Horizon : next day. Predictors use only information up to day t-1, plus the
#           promotion/holiday flags of day t (treated as known in advance - an
#           assumption stated in the report).
# Model   : logistic regression (interpretable odds ratios) vs a baseline that
#           predicts each product's historical event frequency up to t-1.
# Split   : chronological - fit on training days up to 14 days before the end of
#           the training period, choose the decision threshold on the last 14
#           training days (validation), report final metrics on the eval split.
# Note    : there is NO inventory data. The model learns historical sell-out
#           patterns, not current stock on hand.

RP_RISK_X <- c("so_rate7", "so_hours7", "yest_event", "demand_ratio", "promo", "holiday_flag", "weekend")

rp_risk_frame <- function(d) {
  d$weekend <- as.integer(d$weekday >= 6)
  d[stats::complete.cases(d[, c("event", RP_RISK_X, "hist_freq")]), ]
}

rp_auc <- function(p, y) {
  if (length(unique(y)) < 2) return(NA_real_)
  r <- rank(p); n1 <- sum(y == 1); n0 <- sum(y == 0)
  (sum(r[y == 1]) - n1 * (n1 + 1) / 2) / (n1 * n0)
}

rp_class_metrics <- function(p, y, thr) {
  pred <- as.integer(p >= thr)
  tp <- sum(pred == 1 & y == 1); fp <- sum(pred == 1 & y == 0)
  fn <- sum(pred == 0 & y == 1); tn <- sum(pred == 0 & y == 0)
  prec <- if (tp + fp) tp / (tp + fp) else NA_real_
  rec <- if (tp + fn) tp / (tp + fn) else NA_real_
  f1 <- if (!is.na(prec) && !is.na(rec) && (prec + rec) > 0) 2 * prec * rec / (prec + rec) else NA_real_
  eps <- 1e-6; pc <- pmin(pmax(p, eps), 1 - eps)
  c(n = length(y), base_rate = mean(y), threshold = thr, AUC = rp_auc(p, y),
    brier = mean((p - y)^2), log_loss = -mean(y * log(pc) + (1 - y) * log(1 - pc)),
    precision = prec, recall = rec, F1 = f1, TP = tp, FP = fp, FN = fn, TN = tn)
}

rp_fit_risk <- function(d) {
  f <- rp_risk_frame(d)
  train_days <- sort(unique(f$dt[f$split == "train"]))
  val_start <- utils::tail(train_days, 14)[1]
  fit_set <- f[f$split == "train" & f$dt < val_start, ]
  val_set <- f[f$split == "train" & f$dt >= val_start, ]
  test_set <- f[f$split == "eval", ]
  form <- stats::as.formula(paste("event ~", paste(RP_RISK_X, collapse = " + ")))
  m <- stats::glm(form, data = fit_set, family = stats::binomial())
  p_val <- stats::predict(m, val_set, type = "response")
  # threshold maximising F1 on validation (never on the test set)
  grid <- seq(0.05, 0.9, by = 0.01)
  f1s <- vapply(grid, function(t) rp_class_metrics(p_val, val_set$event, t)[["F1"]], 0)
  thr <- if (all(is.na(f1s))) 0.5 else grid[which.max(f1s)]
  f1b <- vapply(grid, function(t) rp_class_metrics(val_set$hist_freq, val_set$event, t)[["F1"]], 0)
  thr_b <- if (all(is.na(f1b))) 0.5 else grid[which.max(f1b)]
  p_test <- stats::predict(m, test_set, type = "response")
  metrics <- rbind(
    logistic_validation = rp_class_metrics(p_val, val_set$event, thr),
    logistic_test = rp_class_metrics(p_test, test_set$event, thr),
    frequency_baseline_test = rp_class_metrics(test_set$hist_freq, test_set$event, thr_b)
  )
  ci <- suppressMessages(stats::confint.default(m))
  coefs <- tibble::tibble(term = names(stats::coef(m)), estimate = unname(stats::coef(m)),
                          odds_ratio = exp(estimate), or_lo95 = exp(ci[, 1]), or_hi95 = exp(ci[, 2]),
                          p_value = summary(m)$coefficients[, 4])
  calib <- tibble::tibble(p = c(p_val, p_test), y = c(val_set$event, test_set$event)) |>
    dplyr::mutate(bin = cut(p, breaks = c(0, 0.1, 0.2, 0.3, 0.5, 0.7, 1), include.lowest = TRUE)) |>
    dplyr::group_by(bin) |>
    dplyr::summarise(n = dplyr::n(), mean_pred = mean(p), observed_rate = mean(y), .groups = "drop")
  list(model = m, threshold = thr, metrics = metrics, coefs = coefs, calibration = calib,
       windows = list(fit = range(fit_set$dt), validation = range(val_set$dt), test = range(test_set$dt)),
       class_balance = c(fit = mean(fit_set$event), validation = mean(val_set$event), test = mean(test_set$event)))
}

# Risk for the day after the data ends. Unknown future flags are set to 0
# (no promotion, no holiday) - stated in the app.
rp_risk_next <- function(d, fit) {
  last <- d |>
    dplyr::group_by(product_id) |>
    dplyr::arrange(dt, .by_group = TRUE) |>
    dplyr::summarise(
      so_rate7 = mean(utils::tail(event, 7)), so_hours7 = mean(utils::tail(stock_h, 7)),
      yest_event = utils::tail(event, 1),
      demand_ratio = mean(utils::tail(latent, 7)) / max(mean(utils::tail(latent, 28)), 1e-6),
      next_dt = max(dt) + 1, .groups = "drop")
  last$promo <- 0L; last$holiday_flag <- 0L
  last$weekend <- as.integer(as.integer(format(last$next_dt, "%u")) >= 6)
  last$risk <- stats::predict(fit$model, last, type = "response")
  last$risk_flag <- as.integer(last$risk >= fit$threshold)
  last
}
