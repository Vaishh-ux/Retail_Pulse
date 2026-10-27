# Store catalogue validation, merging, status and the stockout simulator (R/inventory.R)

test_that("the template and sample pass validation", {
  v <- inv_validate(inv_template(), valid_pids = 1:1000)
  expect_true(v$ok); expect_length(v$errors[[1]], 0)
  s <- inv_sample(as.Date("2026-10-27"))
  expect_true(all(s$source == "sample")); expect_true(all(is.na(s$linked_product_id)))   # never auto-linked to research data
  v2 <- inv_validate(s[, INV_COLS], valid_pids = 1:1000)
  expect_true(all(lengths(v2$errors) == 0))
})

test_that("missing required columns are a file-level error", {
  v <- inv_validate(data.frame(sku = "A", price = "1"))
  expect_false(v$ok); expect_match(v$file_error, "Product name")
  expect_match(v$file_error, "Stock on hand")
  expect_false(inv_validate(data.frame(sku = character(), name = character(), stock = character()))$ok)
})

test_that("row errors catch missing ids, bad numbers, duplicates, dates and unknown links", {
  df <- data.frame(sku = c("A1", "", "A1", "B2", "C3", "D4", "E5", "F6"),
                   name = c("Milk", "Bread", "Milk again", "", "Eggs", "Jam", "Tea", "Rice"),
                   stock = c("5", "3", "2", "1", "-4", "2.5", "x", "7"),
                   price = c("1.2", "", "", "", "", "abc", "", ""),
                   lead_time_days = c("2", "", "", "", "", "", "", "400"),
                   expiry_date = c("2026-11-01", "", "", "", "", "", "31/12/2026", ""),
                   linked_product_id = c("P5", "", "", "", "", "", "", "99999"), stringsAsFactors = FALSE)
  v <- inv_validate(df, existing_skus = "f6", valid_pids = c(4L, 5L))
  e <- v$errors
  expect_length(e[[1]], 0); expect_equal(v$rows$linked_product_id[1], 5L)
  expect_match(e[[2]], "SKU is missing", all = FALSE)
  expect_match(e[[3]], "more than once", all = FALSE)
  expect_match(e[[4]], "name is missing", all = FALSE)
  expect_match(e[[5]], "negative", all = FALSE)
  expect_match(e[[6]], "whole number", all = FALSE); expect_match(e[[6]], "Price", all = FALSE)
  expect_match(e[[7]], "not a number", all = FALSE); expect_match(e[[7]], "Expiry", all = FALSE)
  expect_match(e[[8]], "Lead time", all = FALSE); expect_match(e[[8]], "does not exist", all = FALSE)
  expect_true(v$duplicate_existing[8])                      # case-insensitive match with existing "f6"
})

test_that("column names are matched flexibly", {
  v <- inv_validate(data.frame(`Product ID` = "Z1", `Product Name` = "Oats", Quantity = "3", check.names = FALSE))
  expect_true(v$ok); expect_equal(v$rows$sku, "Z1"); expect_equal(v$rows$stock, 3)
})

test_that("merging never adds invalid rows and does not overwrite unless asked", {
  cat <- inv_sample(as.Date("2026-10-27"))
  df <- data.frame(sku = c("SAMPLE-001", "NEW-1", "BAD"), name = c("Milk (new price)", "Butter", "Bad"), stock = c("50", "3", "-1"),
                   price = c("9.99", "", ""), stringsAsFactors = FALSE)
  v <- inv_validate(df, existing_skus = cat$sku)
  m1 <- inv_merge(cat, v, "skip")
  expect_equal(m1$added, 1); expect_equal(m1$skipped_duplicates, 1); expect_equal(m1$rejected, 1)
  expect_equal(m1$catalogue$stock[m1$catalogue$sku == "SAMPLE-001"], 14)      # untouched
  expect_false("BAD" %in% m1$catalogue$sku)
  m2 <- inv_merge(cat, v, "update")
  expect_equal(m2$updated, 1); expect_equal(m2$catalogue$stock[m2$catalogue$sku == "SAMPLE-001"], 50)
  expect_equal(nrow(m2$catalogue), nrow(cat) + 1)
})

test_that("status uses only the user's own numbers", {
  cat <- inv_sample(as.Date("2026-10-27"))
  st <- inv_status(cat, today = as.Date("2026-10-27"))
  expect_equal(st[cat$sku == "SAMPLE-008"], "Out of stock")
  expect_equal(st[cat$sku == "SAMPLE-005"], "At or below reorder level")     # 4 <= 6
  expect_equal(st[cat$sku == "SAMPLE-006"], "Expires soon")                  # 9 > 6, expires in 3 days
  expect_equal(st[cat$sku == "SAMPLE-004"], "OK")
})

test_that("simulator arithmetic", {
  s <- inv_simulate(stock = 10, demand = rep(4, 7), lead = 2, delay = 0, safety = 3)
  expect_equal(s$days_left, 2.5)                     # 10 / 4
  expect_equal(s$stockout_day, 3L)
  expect_equal(s$below_safety_day, 2L)               # 10 -> 6 -> 2
  expect_equal(s$stock_at_arrival, 2)
  expect_false(s$runs_out_before_arrival)
  s2 <- inv_simulate(10, rep(4, 7), lead = 2, delay = 2)
  expect_true(s2$runs_out_before_arrival); expect_equal(s2$unmet_before_arrival, 6)   # 16 demanded by day 4, 10 in stock
  z <- inv_simulate(5, rep(0, 7))
  expect_true(is.infinite(z$days_left)); expect_true(is.na(z$stockout_day))
  expect_equal(inv_simulate(0, rep(1, 7))$days_left, 0)
  expect_error(inv_simulate(-1, rep(1, 7)))
  expect_equal(inv_simulate(10, rep(4, 7), safety = 20)$below_safety_day, 0L)
  far <- inv_simulate(100, rep(1, 7), lead = 10)
  expect_true(is.na(far$stock_at_arrival))           # delivery beyond the horizon
})

test_that("demand path applies the multiplier and a weekday pattern with mean 1", {
  expect_equal(inv_demand_path(4, 7, 1.5), rep(6, 7))
  p <- inv_demand_path(10, 14, 1, pattern = c(1, 1, 1, 1, 1, 2, 2))
  expect_equal(length(p), 14); expect_equal(mean(p[1:7]), 10)
  expect_equal(inv_demand_path(-3, 5), rep(0, 5))
})

test_that("browser storage round-trip and bad input", {
  cat <- inv_sample(as.Date("2026-10-27")); cat$linked_product_id[2] <- 108L
  back <- inv_from_json(as.character(inv_to_json(cat)))
  expect_equal(back$sku, cat$sku); expect_equal(back$stock, cat$stock); expect_equal(back$linked_product_id, cat$linked_product_id)
  expect_equal(back$expiry_date, cat$expiry_date)
  expect_null(inv_from_json("{not json"))
  expect_equal(nrow(inv_from_json('{"version":1,"rows":[]}')), 0)
  bad <- inv_from_json('{"version":1,"rows":[{"sku":"X","name":"n","stock":-5},{"sku":"Y","name":"m","stock":2}]}')
  expect_equal(bad$sku, "Y")                         # negative stock dropped on load
})

test_that("expiry is counted independently of the stock status", {
  cat <- inv_sample(as.Date("2026-10-27"))
  e <- inv_expiring(cat, today = as.Date("2026-10-27"))
  expect_true(e[cat$sku == "SAMPLE-002"])            # bread: low stock AND expires in 2 days
  expect_true(e[cat$sku == "SAMPLE-006"]); expect_false(e[cat$sku == "SAMPLE-004"])
  expect_equal(sum(e), 2)
})
