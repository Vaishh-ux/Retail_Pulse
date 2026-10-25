# Anomaly detection: robust z-score against each product's own recent baseline --
# Sales are first divided by the product's weekday factor, estimated from the
# previous 56 days only (so weekends are not flagged just for being weekends).
# reference  = median of weekday-adjusted RECORDED sales on the previous 28 days
#              with no trading-hour stockout (so censored days do not drag it down)
# spread     = 1.4826 x MAD of the same window, floored to avoid division by ~0
# z          = (recorded sales - reference) / spread
# Only days with >= 10 baseline days are scored. The threshold is configurable.

# Leakage-safe weekday factor for day t: using only in-stock days in the 56 days
# BEFORE t, factor = mean(sales on t's weekday) / mean(all sales), shrunk towards
# 1 with weight k so that a weekday seen only once or twice stays close to 1.
rp_weekday_factor_past <- function(dt, wd, x, instock, lookback = 56, k = 4) {
  n <- length(dt); f <- rep(1, n)
  for (i in seq_len(n)) {
    w <- which(dt < dt[i] & dt >= dt[i] - lookback & instock == 1L)
    if (length(w) < 14) next
    m_all <- mean(x[w]); if (m_all <= 0) next
    same <- w[wd[w] == wd[i]]
    if (!length(same)) next
    raw <- mean(x[same]) / m_all
    f[i] <- (length(same) * raw + k * 1) / (length(same) + k)
  }
  pmax(f, 0.2)
}

rp_anomaly_scores <- function(d, window = 28L, min_days = 10L) {
  d |>
    dplyr::select(-dplyr::any_of("wd_factor")) |>
    dplyr::group_by(product_id) |>
    dplyr::arrange(dt, .by_group = TRUE) |>
    dplyr::mutate(
      wd_factor = rp_weekday_factor_past(dt, weekday, sale_amount, 1L - any_stockout),
      .adj = sale_amount / wd_factor,
      .ref_x = ifelse(any_stockout == 0L, .adj, NA_real_),
      ref_n = slider::slide_dbl(.ref_x, function(x) sum(!is.na(x)), .before = window, .after = -1),
      .ref = slider::slide_dbl(.ref_x, function(x) if (sum(!is.na(x)) < 1) NA_real_ else stats::median(x, na.rm = TRUE),
                               .before = window, .after = -1),
      .mad = slider::slide_dbl(.ref_x, function(x) if (sum(!is.na(x)) < 2) NA_real_ else stats::mad(x, na.rm = TRUE),
                               .before = window, .after = -1),
      .spread = pmax(.mad, 0.15 * .ref, 0.1),
      z = ifelse(ref_n >= min_days, (.adj - .ref) / .spread, NA_real_),
      reference = .ref * wd_factor,          # expected recorded sales for this weekday
      spread = .spread * wd_factor
    ) |>
    dplyr::select(-.adj, -.ref_x, -.ref, -.mad, -.spread) |>
    dplyr::ungroup()
}

# Label every flagged day with the strongest documented explanation
rp_classify_anomalies <- function(d, z_thr = 3, rain_q = NULL) {
  rain_q <- rain_q %||% stats::quantile(d$precpt, 0.9, na.rm = TRUE)
  out <- d[!is.na(d$z) & abs(d$z) >= z_thr, ]
  if (!nrow(out)) return(tibble::tibble())
  dirn <- ifelse(out$z > 0, "surge", "drop")
  stock_expl <- out$stock_h >= 4 | out$stockout_day == 1L
  cause <- dplyr::case_when(
    dirn == "drop" & stock_expl ~ "Stockout (supply-side)",
    dirn == "surge" & out$promo == 1L ~ "Promotion",
    out$holiday_flag == 1L ~ "Holiday",
    dirn == "drop" & out$precpt >= rain_q ~ "Possibly heavy rain",
    TRUE ~ "Unexplained"
  )
  expl <- dplyr::case_when(
    cause == "Stockout (supply-side)" ~ sprintf("Out of stock for %d of 16 trading hours; recorded sales understate demand.", out$stock_h),
    cause == "Promotion" ~ sprintf("Promotion active (discount %.0f%% off). Higher sales are expected.", 100 * out$promo_depth),
    cause == "Holiday" ~ "Holiday flag set on this day; demand often shifts on holidays.",
    cause == "Possibly heavy rain" ~ sprintf("Precipitation %.1f is in the top 10%% of days; a weather effect is possible but not confirmed.", out$precpt),
    TRUE ~ "No stockout, promotion, holiday or heavy rain recorded. Cause unknown; worth checking (quality, pricing, display)."
  )
  tibble::tibble(product_id = out$product_id, dt = out$dt, direction = dirn,
                 observed = round(out$sale_amount, 3), expected = round(out$reference, 3),
                 deviation = round(out$sale_amount - out$reference, 3), z = round(out$z, 2),
                 cause = cause, explanation = expl,
                 method = sprintf("Robust z vs weekday-adjusted 28-day in-stock median; |z| >= %.1f", z_thr),
                 note = "Statistical unusualness only; not a confirmed operational problem.")
}

# Sustained rises: at least `k` consecutive days with z >= z_run
rp_sustained_runs <- function(d, z_run = 2, k = 3L) {
  d |>
    dplyr::group_by(product_id) |>
    dplyr::arrange(dt, .by_group = TRUE) |>
    dplyr::mutate(hi = !is.na(z) & z >= z_run,
                  run_id = cumsum(!hi)) |>
    dplyr::filter(hi) |>
    dplyr::group_by(product_id, run_id) |>
    dplyr::summarise(start = min(dt), end = max(dt), days = dplyr::n(), max_z = max(z), .groups = "drop") |>
    dplyr::filter(days >= k) |>
    dplyr::select(-run_id)
}
