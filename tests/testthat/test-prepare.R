test_that("synthetic data has exactly the FreshRetailNet-50K schema", {
  raw <- fixture()$raw
  expect_true(all(RP_SCHEMA %in% names(raw)))
  expect_true(all(lengths(raw$hours_sale) == 24))
  expect_true(all(lengths(raw$hours_stock_status) == 24))
  expect_setequal(unique(raw$split), c("train", "eval"))
})

test_that("validation removes duplicates and repairs hourly/daily mismatches", {
  f <- fixture(); rep <- f$v$report
  expect_gte(rep$duplicates_removed, 1)
  expect_equal(anyDuplicated(paste(f$v$clean$product_id, f$v$clean$dt)), 0)
  # after cleaning, the daily total equals the hourly sum
  expect_equal(f$v$clean$sale_amount, rowSums(f$v$H), tolerance = 1e-6)
  expect_equal(nrow(f$v$H), nrow(f$v$clean))
})

test_that("rows with hourly lists of the wrong length are dropped", {
  cfg <- cfg_test()
  ok <- make_row(1L, "2024-04-01", rep(0.1, 24), rep(0, 24))
  bad <- make_row(1L, "2024-04-02", rep(0.1, 24), rep(0, 24)); bad$hours_sale <- list(rep(0.1, 23))
  v <- rp_validate_and_clean(dplyr::bind_rows(ok, bad), cfg)
  expect_equal(v$report$hourly_wrong_length, 1)
  expect_equal(nrow(v$clean), 1)
})

test_that("stockout hours are counted only between 06:00 and 21:59", {
  cfg <- cfg_test()
  st <- rep(0, 24); st[1:6] <- 1; st[23:24] <- 1        # night only
  st2 <- st; st2[15:18] <- 1                            # + 4 trading hours (14:00-17:59)
  v <- rp_validate_and_clean(dplyr::bind_rows(make_row(1L, "2024-04-01", rep(0.1, 24), st),
                                              make_row(1L, "2024-04-02", rep(0.1, 24), st2)), cfg)
  expect_equal(v$clean$stock_h, c(0L, 4L))
  expect_equal(v$clean$any_stockout, c(0L, 1L))
})

test_that("rolling and lag features use only past days (no leakage)", {
  d <- fixture()$d |> dplyr::filter(product_id == min(product_id)) |> dplyr::arrange(dt)
  i <- 40
  expect_equal(d$roll7[i], mean(d$latent[(i - 7):(i - 1)]), tolerance = 1e-9)
  expect_equal(d$lag1[i], d$latent[i - 1])
  expect_equal(d$so_rate7[i], mean(d$event[(i - 7):(i - 1)]), tolerance = 1e-9)
  # changing today's value must not change today's features
  d2 <- fixture()$d; j <- which(d2$product_id == min(d2$product_id))[i]
  d2$latent[j] <- d2$latent[j] + 100
  d2 <- rp_add_features(d2 |> dplyr::select(-c(lag1, lag7, roll7, roll28, event, so_rate7, so_hours7, yest_event, hist_freq, demand_ratio)), 4)
  expect_equal(d2$roll7[j], d$roll7[i], tolerance = 1e-9)
})
