# Sell-out timing ---------------------------------------------------------------
# For each product-day, the "sell-out hour" is the first trading hour (06-21)
# whose stock status is 1. Days that stay in stock all day are censored at 22.
# Kaplan-Meier curves give the probability of still being in stock at each hour.

rp_sellout_times <- function(d, S, cfg) {
  tr <- cfg$trading_idx
  first_out <- apply(S[, tr, drop = FALSE], 1, function(r) { w <- which(r == 1); if (length(w)) w[1] else NA_integer_ })
  tibble::tibble(product_id = d$product_id, dt = d$dt, weektype = d$weektype,
                 time = ifelse(is.na(first_out), 22, 5 + first_out),  # 0-based hour of first stockout
                 event = as.integer(!is.na(first_out)))
}

rp_sellout_curves <- function(times) {
  times |>
    dplyr::group_by(product_id, weektype) |>
    dplyr::group_modify(function(g, k) {
      if (sum(g$event) == 0) return(tibble::tibble(hour = c(6, 22), surv = c(1, 1)))
      fit <- survival::survfit(survival::Surv(time, event) ~ 1, data = g)
      tibble::tibble(hour = c(6, fit$time), surv = c(1, fit$surv))
    }) |>
    dplyr::ungroup()
}

rp_sellout_summary <- function(times) {
  times |>
    dplyr::group_by(product_id) |>
    dplyr::group_modify(function(g, k) {
      fit <- survival::survfit(survival::Surv(time, event) ~ 1, data = g)
      s18 <- summary(fit, times = 18, extend = TRUE)$surv
      med <- unname(summary(fit)$table["median"])
      tibble::tibble(days = nrow(g), sellout_days = sum(g$event), sellout_share = mean(g$event),
                     median_sellout_hour = ifelse(is.na(med) | med >= 22, NA_real_, med),
                     p_instock_18 = s18,
                     typical_first_out = if (sum(g$event)) stats::median(g$time[g$event == 1]) else NA_real_)
    }) |>
    dplyr::ungroup()
}
