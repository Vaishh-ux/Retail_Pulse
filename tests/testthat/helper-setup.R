# Test fixtures: small SYNTHETIC data (test data only, never the main dataset)
root <- normalizePath(file.path(testthat::test_path(), "..", ".."))
for (f in list.files(file.path(root, "R"), pattern = "\\.R$", full.names = TRUE)) source(f)
suppressPackageStartupMessages(library(dplyr))
cfg_test <- function() { c <- rp_config(); c$root <- root; c }

fixture <- local({
  cache <- NULL
  function() {
    if (is.null(cache)) {
      cfg <- cfg_test()
      raw <- rp_make_synthetic(n_stores = 1, n_products = 8, seed = 11)
      v <- rp_validate_and_clean(raw, cfg)
      d <- v$clean; tr <- d$split == "train"
      pf <- rp_fit_profiles(d[tr, ], v$H[tr, , drop = FALSE])
      d <- rp_latent_demand(d, v$H, v$S, cfg, pf)
      d <- rp_add_features(d, cfg$risk_event_h)
      d <- rp_anomaly_scores(d)
      cache <<- list(cfg = cfg, raw = raw, v = v, d = d, pf = pf)
    }
    cache
  }
})

# one hand-made product-day row in the dataset's schema
make_row <- function(pid, date, hours, status, split = "train") {
  tibble::tibble(city_id = 0L, store_id = 0L, management_group_id = 0L, first_category_id = 1L,
                 second_category_id = 1L, third_category_id = 1L, product_id = pid, dt = date,
                 sale_amount = sum(hours), hours_sale = list(hours), stock_hour6_22_cnt = as.integer(sum(status[7:22])),
                 hours_stock_status = list(as.integer(status)), discount = 1, holiday_flag = 0L, activity_flag = 0L,
                 precpt = 0, avg_temperature = 20, avg_humidity = 70, avg_wind_level = 1.5, split = split)
}
