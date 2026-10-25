ind_row <- function(...) {
  base <- tibble::tibble(product_id = 1L, obs7 = 10, latent7 = 10, stockout_days7 = 0, lost_share7 = 0, fc7 = 10,
                         unexplained_drops7 = 0L, unexplained_surges7 = 0L, last_anomaly = as.Date(NA), risk = 0.05,
                         cv_wape = 0.2, full_instock_days = 60, zero_sale_share = 0.05, fc_ratio = 1)
  utils::modifyList(base, list(...))
}

test_that("a product with nothing unusual gets 'Maintain current approach'", {
  r <- rp_recommend(ind_row(), risk_threshold = 0.3)
  expect_equal(r$action, "Maintain current approach")
  expect_match(r$rule, "^R6")
})

test_that("frequent stockouts trigger 'replenish earlier' with evidence and rule", {
  r <- rp_recommend(ind_row(stockout_days7 = 4, lost_share7 = 0.25, latent7 = 13.3), risk_threshold = 0.3)
  x <- r[r$action == "Consider replenishing earlier", ]
  expect_equal(nrow(x), 1); expect_equal(x$urgency, "High")
  expect_match(x$rule, "^R1"); expect_match(x$evidence, "Stockout days")
  expect_false(grepl("order [0-9]|units to order|reorder quantity", x$reason))
})

test_that("unexplained drops, surges and unreliable forecasts each fire their own rule", {
  expect_true("Investigate unexplained sales drop" %in% rp_recommend(ind_row(unexplained_drops7 = 1L))$action)
  expect_true("Review possible demand surge" %in% rp_recommend(ind_row(fc_ratio = 1.4, fc7 = 14))$action)
  low <- rp_recommend(ind_row(cv_wape = NA_real_))
  expect_true("Use caution: forecast unreliable" %in% low$action)
  expect_equal(unique(low$reliability), "Low")
})

test_that("priority weights reorder products but never change urgency", {
  ind <- dplyr::bind_rows(ind_row(product_id = 1L, stockout_days7 = 3, lost_share7 = 0.05, risk = 0.9),
                          ind_row(product_id = 2L, stockout_days7 = 3, lost_share7 = 0.15, risk = 0.1))
  a <- rp_recommend(ind, list(w_lost = 0, w_risk = 3), risk_threshold = 0.5)
  b <- rp_recommend(ind, list(w_lost = 3, w_risk = 0), risk_threshold = 0.5)
  expect_equal(a$product_id[1], 1L); expect_equal(b$product_id[1], 2L)
  expect_equal(sort(a$urgency), sort(b$urgency))
})

test_that("sell-out times are censored at 22 when a product stays in stock", {
  cfg <- cfg_test()
  S <- matrix(0, 2, 24); S[2, 16:22] <- 1                       # out from 15:00
  d <- tibble::tibble(product_id = 1L, dt = as.Date(c("2024-04-01", "2024-04-02")), weektype = "weekday")
  t <- rp_sellout_times(d, S, cfg)
  expect_equal(t$time, c(22, 15)); expect_equal(t$event, c(0L, 1L))
})

test_that("replay alerts never use future hours", {
  rt <- tibble::tibble(product_id = 1L, dt = as.Date("2024-06-26"), hour = 0:23, sales = 0,
                       out = c(rep(0, 14), rep(1, 10)), cum_obs = 0, cum_exp = seq(0, 2.3, by = 0.1),
                       cum_lo = seq(0, 2.3, by = 0.1) * 0.8, cum_hi = seq(0, 2.3, by = 0.1) * 1.2, peak = 0L)
  a <- rp_replay_alerts(rt, cfg_test())
  so <- a[a$type == "Out of stock", ]
  expect_equal(so$hour, 14)                                      # raised at the onset hour, not earlier
  below <- a[a$type == "Below expected", ]
  expect_true(all(below$hour >= 12))
})

test_that("the surge reason names the trigger that actually fired", {
  r1 <- rp_recommend(ind_row(unexplained_surges7 = 1L, fc_ratio = 0.99))
  x <- r1[r1$action == "Review possible demand surge", ]
  expect_match(x$reason, "far above normal"); expect_false(grepl("99%", x$reason))
  r2 <- rp_recommend(ind_row(fc_ratio = 1.4, fc7 = 14))
  expect_match(r2$reason[r2$action == "Review possible demand surge"], "140%")
})
