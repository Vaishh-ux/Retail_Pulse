# Validation, cleaning and feature engineering ---------------------------------

# Run every data-quality check on the raw store table and return
# list(clean = tibble, H = sales matrix, S = stock-status matrix, report = list)
rp_validate_and_clean <- function(raw, cfg) {
  rep <- list()
  rep$rows_raw <- nrow(raw)
  rep$columns_missing <- setdiff(RP_SCHEMA, names(raw))
  scalar_cols <- setdiff(RP_SCHEMA, c("hours_sale", "hours_stock_status"))
  rep$missing_by_column <- vapply(raw[scalar_cols], function(x) sum(is.na(x)), 0L)

  # types
  raw$dt <- as.Date(raw$dt)
  int_cols <- c("city_id", "store_id", "management_group_id", "first_category_id",
                "second_category_id", "third_category_id", "product_id",
                "stock_hour6_22_cnt", "holiday_flag", "activity_flag")
  for (cc in int_cols) raw[[cc]] <- as.integer(raw[[cc]])

  # duplicates on (product, date): keep the first occurrence
  key <- paste(raw$product_id, raw$dt)
  dup <- duplicated(key)
  rep$duplicates_removed <- sum(dup)
  raw <- raw[!dup, ]

  H <- rp_list_to_matrix(raw$hours_sale)
  S <- rp_list_to_matrix(raw$hours_stock_status)
  bad_len <- union(attr(H, "bad_length"), attr(S, "bad_length"))
  rep$hourly_wrong_length <- length(bad_len)
  if (length(bad_len)) { raw <- raw[-bad_len, ]; H <- H[-bad_len, , drop = FALSE]; S <- S[-bad_len, , drop = FALSE] }

  # negative or impossible values
  neg <- which(raw$sale_amount < 0 | rowSums(H < 0, na.rm = TRUE) > 0)
  rep$negative_sales_rows <- length(neg)
  H[H < 0] <- 0; raw$sale_amount[raw$sale_amount < 0] <- 0
  rep$discount_out_of_range <- sum(raw$discount <= 0 | raw$discount > 1, na.rm = TRUE)
  raw$discount[is.na(raw$discount) | raw$discount <= 0 | raw$discount > 1] <- 1
  S[is.na(S)] <- 0; S[S != 0] <- 1

  # hourly-to-daily consistency: the hourly record is treated as authoritative
  hsum <- rowSums(H, na.rm = TRUE)
  mism <- abs(hsum - raw$sale_amount) > 0.051
  rep$hourly_daily_mismatch <- sum(mism)
  raw$sale_amount_reported <- raw$sale_amount
  raw$sale_amount <- round(hsum, 4)

  # stock-hour count consistency (dataset definition: hours 06-21, 16 hours)
  recount <- rowSums(S[, cfg$trading_idx, drop = FALSE])
  rep$stock_count_mismatch <- sum(recount != raw$stock_hour6_22_cnt, na.rm = TRUE)
  raw$stock_h <- as.integer(recount)

  # weather: impute missing with the store's median (documented)
  for (cc in c("precpt", "avg_temperature", "avg_humidity", "avg_wind_level")) {
    n_na <- sum(is.na(raw[[cc]]))
    if (n_na) raw[[cc]][is.na(raw[[cc]])] <- stats::median(raw[[cc]], na.rm = TRUE)
    rep[[paste0("imputed_", cc)]] <- n_na
  }

  # calendar completeness per product
  rng <- range(raw$dt)
  full_n <- as.integer(diff(rng)) + 1L
  per_prod <- table(raw$product_id)
  rep$products <- length(per_prod)
  rep$date_min <- format(rng[1]); rep$date_max <- format(rng[2])
  rep$missing_product_days <- sum(full_n - as.integer(per_prod))

  # order by product/date and keep matrices aligned
  o <- order(raw$product_id, raw$dt)
  raw <- raw[o, ]; H <- H[o, , drop = FALSE]; S <- S[o, , drop = FALSE]
  raw$hours_sale <- NULL; raw$hours_stock_status <- NULL

  # derived flags
  raw$weekday <- as.integer(format(raw$dt, "%u"))                 # 1 = Monday
  raw$weektype <- ifelse(raw$weekday >= 6, "weekend", "weekday")
  raw$promo <- as.integer(raw$discount < 1 | raw$activity_flag == 1L)
  raw$promo_depth <- round(1 - raw$discount, 4)
  raw$any_stockout <- as.integer(raw$stock_h > 0)
  raw$stockout_day <- as.integer(raw$stock_h >= cfg$stockout_day_h)
  raw$full_instock <- as.integer(raw$stock_h == 0 & raw$sale_amount > 0)
  raw$zero_sale <- as.integer(raw$sale_amount == 0)

  rep$rows_clean <- nrow(raw)
  rep$zero_sale_share <- mean(raw$zero_sale)
  rep$stockout_hour_rate <- sum(raw$stock_h) / (nrow(raw) * length(cfg$trading_idx))
  rep$share_days_any_stockout <- mean(raw$any_stockout)
  rep$share_stockout_days <- mean(raw$stockout_day)
  rep$promo_day_share <- mean(raw$promo)

  per_product <- raw |>
    dplyr::group_by(product_id) |>
    dplyr::summarise(days = dplyr::n(), zero_sale_share = mean(zero_sale),
                     stockout_hour_rate = sum(stock_h) / (dplyr::n() * 16),
                     full_instock_days = sum(full_instock),
                     promo_days = sum(promo), .groups = "drop")
  list(clean = raw, H = H, S = S, report = rep, per_product = per_product)
}

# Leakage-safe features: every rolling/lag value at day t uses only days < t
rp_add_features <- function(d, event_h) {
  d |>
    dplyr::group_by(product_id) |>
    dplyr::arrange(dt, .by_group = TRUE) |>
    dplyr::mutate(
      lag1 = dplyr::lag(latent, 1),
      lag7 = dplyr::lag(latent, 7),
      roll7 = slider::slide_dbl(latent, mean, .before = 7, .after = -1, .complete = TRUE),
      roll28 = slider::slide_dbl(latent, mean, .before = 28, .after = -1, .complete = TRUE),
      event = as.integer(stock_h >= event_h),
      so_rate7 = slider::slide_dbl(event, mean, .before = 7, .after = -1, .complete = TRUE),
      so_hours7 = slider::slide_dbl(stock_h, mean, .before = 7, .after = -1, .complete = TRUE),
      yest_event = dplyr::lag(event, 1),
      hist_freq = dplyr::lag(cumsum(event) / seq_along(event), 1),
      demand_ratio = roll7 / pmax(roll28, 1e-6)
    ) |>
    dplyr::ungroup()
}
