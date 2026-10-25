# Simulated hourly replay ---------------------------------------------------------
# Replays the HISTORICAL hourly records of the evaluation week. The expected curve
# for each day comes from the forecast made with training data only (i.e. before
# the replayed week), spread over the day with the product's hourly profile.
# Alerts at hour h use only observations up to hour h, so nothing from the future
# is used. This is a demonstration, NOT a live data feed.

rp_replay_table <- function(d, H, S, pf, fc_eval_chosen, cfg) {
  ev <- which(d$split == "eval")
  rows <- lapply(ev, function(i) {
    prof <- rp_profile(pf, d$product_id[i], d$weektype[i])
    f <- fc_eval_chosen[fc_eval_chosen$product_id == d$product_id[i] & fc_eval_chosen$dt == d$dt[i], ]
    if (!nrow(f)) return(NULL)
    cs <- cumsum(prof)
    tibble::tibble(product_id = d$product_id[i], dt = d$dt[i], hour = 0:23,
                   sales = H[i, ], out = as.integer(S[i, ]),
                   cum_obs = cumsum(H[i, ]), cum_exp = f$mean * cs,
                   cum_lo = f$lo80 * cs, cum_hi = f$hi80 * cs,
                   peak = as.integer(rank(-prof[cfg$trading_idx], ties.method = "first")[match(0:23, 6:21)] <= 4 & 0:23 %in% 6:21))
  })
  rt <- dplyr::bind_rows(rows)
  rt$peak[is.na(rt$peak)] <- 0L
  rt$ts <- as.POSIXct(paste(rt$dt, sprintf("%02d:00:00", rt$hour)), tz = "UTC")
  rt
}

rp_replay_alerts <- function(rt, cfg) {
  trading <- 6:21
  rt |>
    dplyr::group_by(product_id, dt) |>
    dplyr::arrange(hour, .by_group = TRUE) |>
    dplyr::group_modify(function(g, k) {
      a <- list()
      onset <- which(g$out == 1 & dplyr::lag(g$out, default = 0) == 0 & g$hour %in% trading)
      if (length(onset)) {
        h <- onset[1]
        sev <- if (g$peak[h] == 1) "Critical" else "Info"
        a[[length(a) + 1]] <- tibble::tibble(hour = g$hour[h], severity = sev, type = "Out of stock",
          message = sprintf("Out of stock from %02d:00%s.", g$hour[h], if (sev == "Critical") " (a peak hour for this product)" else ""),
          observed = g$cum_obs[h], expected = g$cum_exp[h])
      }
      instock <- g$out == 0 & g$hour %in% 12:21
      below <- instock & g$cum_obs < g$cum_lo
      above <- instock & g$cum_obs > g$cum_hi
      three <- function(x) which(x & dplyr::lag(x, default = FALSE) & dplyr::lag(x, 2, default = FALSE))
      b <- three(below); u <- three(above)
      if (length(b)) a[[length(a) + 1]] <- tibble::tibble(hour = g$hour[b[1]], severity = "Warning", type = "Below expected",
          message = "Cumulative sales below the expected range for 3 consecutive hours (from 12:00) while in stock.",
          observed = g$cum_obs[b[1]], expected = g$cum_exp[b[1]])
      if (length(u)) a[[length(a) + 1]] <- tibble::tibble(hour = g$hour[u[1]], severity = "Warning", type = "Above expected",
          message = "Cumulative sales above the expected range for 3 consecutive hours (possible surge).",
          observed = g$cum_obs[u[1]], expected = g$cum_exp[u[1]])
      if (!length(a)) return(tibble::tibble())
      dplyr::bind_rows(a)
    }) |>
    dplyr::ungroup() |>
    dplyr::mutate(ts = as.POSIXct(paste(dt, sprintf("%02d:00:00", hour)), tz = "UTC"),
                  observed = round(observed, 3), expected = round(expected, 3)) |>
    dplyr::arrange(ts, dplyr::desc(severity == "Critical"))
}
