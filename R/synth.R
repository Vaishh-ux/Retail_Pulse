# Synthetic demo data --------------------------------------------------------
# Produces tables with EXACTLY the FreshRetailNet-50K schema so that the whole
# pipeline can be developed and tested without the real files.
# Everything generated here is ILLUSTRATIVE. Outputs built from it are marked
# mode = "synthetic" in outputs/manifest.json and the app shows a banner.

rp_make_synthetic <- function(n_stores = 2, n_products = 48, train_days = 90,
                              eval_days = 7, start = as.Date("2024-03-28"),
                              seed = 2026) {
  set.seed(seed)
  dates <- start + 0:(train_days + eval_days - 1)
  holidays <- as.Date(c("2024-04-04", "2024-04-05", "2024-04-06", "2024-05-01",
                        "2024-05-02", "2024-05-03", "2024-05-04", "2024-05-05",
                        "2024-06-10"))
  cat_first <- c(5L, 13L, 28L, 21L)        # four illustrative first-level categories
  rows <- vector("list", n_stores * n_products)
  k <- 0
  for (s in seq_len(n_stores) - 1L) {
    # store-level weather (city level in the real data)
    precpt <- round(pmax(0, rgamma(length(dates), shape = 0.6, rate = 0.25)), 4)
    temp <- round(15 + 12 * (seq_along(dates) / length(dates)) + rnorm(length(dates), 0, 1.2), 2)
    hum <- round(pmin(98, pmax(40, 72 + 1.2 * precpt + rnorm(length(dates), 0, 4))), 2)
    wind <- round(pmax(0.5, rnorm(length(dates), 1.7, 0.3)), 2)
    for (p in seq_len(n_products)) {
      k <- k + 1
      fc <- cat_first[(p - 1) %% length(cat_first) + 1]
      level <- exp(rnorm(1, log(1.6), 0.7))                       # mean daily demand
      trend <- rnorm(1, 0, 0.004)
      wk <- c(0.95, 0.92, 0.95, 1.00, 1.06, 1.20, 1.15)           # Mon..Sun
      # hourly demand profile: morning + evening peaks
      hrs <- 0:23
      prof <- 0.02 + dnorm(hrs, rnorm(1, 9.5, 1), 1.6) * runif(1, 0.6, 1.4) +
        dnorm(hrs, rnorm(1, 18, 1), 2) * runif(1, 0.6, 1.4)
      prof[hrs < 6 | hrs > 22] <- prof[hrs < 6 | hrs > 22] * 0.15
      prof <- prof / sum(prof)
      # promotions: a few spells of 3-5 days
      disc <- rep(1, length(dates)); act <- rep(0L, length(dates))
      for (sp in seq_len(sample(1:3, 1))) {
        st <- sample(seq_along(dates)[-(1:7)], 1); len <- sample(3:5, 1)
        idx <- st:min(length(dates), st + len - 1)
        disc[idx] <- round(runif(1, 0.5, 0.9), 3); act[idx] <- 1L
      }
      stock_buffer <- runif(1, 1.00, 1.45)   # how generously this product is stocked
      surge_start <- if (p == 7) 70 else NA   # one product with a sustained rise
      drop_day <- if (p %in% c(9, 20)) sample(60:95, 1) else NA  # unexplained drops
      d_rows <- vector("list", length(dates))
      for (i in seq_along(dates)) {
        d <- dates[i]
        wd <- as.integer(format(d, "%u"))
        mu <- level * wk[wd] * exp(trend * i) *
          (1 + 2.2 * (1 - disc[i])) * (1 + 0.15 * (d %in% holidays)) *
          (1 - 0.06 * pmin(1, precpt[i] / 10))
        if (!is.na(surge_start) && i >= surge_start) mu <- mu * (1 + 0.04 * (i - surge_start + 1))
        if (!is.na(drop_day) && i == drop_day) mu <- mu * 0.25
        lam <- mu * prof
        dem <- rpois(24, lam * 10) / 10                           # 0.1-unit resolution
        stock <- level * wk[wd] * stock_buffer * runif(1, 0.85, 1.15)
        cum <- cumsum(dem)
        status <- integer(24); sales <- dem
        out_from <- which(cum > stock & hrs >= 6 & hrs <= 21)[1]
        if (!is.na(out_from)) {
          back <- if (runif(1) < 0.3) min(22, out_from + sample(2:4, 1)) else 22
          oh <- out_from:min(back, 22)
          oh <- oh[hrs[oh] <= 21]
          status[oh] <- 1L
          sales[oh] <- 0
          if (out_from > 1) sales[out_from] <- round(max(0, stock - cum[out_from - 1]), 1)
        }
        # overnight hours are often flagged unavailable in the real data
        if (runif(1) < 0.45) status[1:sample(3:6, 1)] <- 1L
        if (runif(1) < 0.30) status[23:24] <- 1L
        sales[status == 1L & (hrs < 6 | hrs > 21)] <- 0
        d_rows[[i]] <- list(dt = format(d, "%Y-%m-%d"), sale_amount = round(sum(sales), 1),
                            hours_sale = round(sales, 1), hours_stock_status = status,
                            stock_hour6_22_cnt = as.integer(sum(status[7:22])),
                            discount = disc[i], holiday_flag = as.integer(d %in% holidays),
                            activity_flag = act[i], precpt = precpt[i],
                            avg_temperature = temp[i], avg_humidity = hum[i],
                            avg_wind_level = wind[i])
      }
      rows[[k]] <- tibble::tibble(
        city_id = 0L, store_id = as.integer(s), management_group_id = 0L,
        first_category_id = fc, second_category_id = fc * 10L + (p %% 3L),
        third_category_id = fc * 100L + (p %% 7L), product_id = as.integer(1000L * s + p),
        dt = vapply(d_rows, `[[`, "", "dt"),
        sale_amount = vapply(d_rows, `[[`, 0, "sale_amount"),
        hours_sale = lapply(d_rows, `[[`, "hours_sale"),
        stock_hour6_22_cnt = vapply(d_rows, `[[`, 0L, "stock_hour6_22_cnt"),
        hours_stock_status = lapply(d_rows, `[[`, "hours_stock_status"),
        discount = vapply(d_rows, `[[`, 0, "discount"),
        holiday_flag = vapply(d_rows, `[[`, 0L, "holiday_flag"),
        activity_flag = vapply(d_rows, `[[`, 0L, "activity_flag"),
        precpt = vapply(d_rows, `[[`, 0, "precpt"),
        avg_temperature = vapply(d_rows, `[[`, 0, "avg_temperature"),
        avg_humidity = vapply(d_rows, `[[`, 0, "avg_humidity"),
        avg_wind_level = vapply(d_rows, `[[`, 0, "avg_wind_level")
      )
    }
  }
  all <- dplyr::bind_rows(rows)
  all$split <- ifelse(as.Date(all$dt) < start + train_days, "train", "eval")
  # A handful of deliberately injected quality problems so that the validation
  # checks have something to detect in demo mode (documented in README).
  n <- nrow(all)
  dup <- all[unique(c(5, min(400, n))), ]
  all <- dplyr::bind_rows(all, dup)
  bad <- unique(c(min(123, n), min(2345, n - 1)))
  all$sale_amount[bad] <- all$sale_amount[bad] + 0.7      # hourly-vs-daily mismatch
  all
}
