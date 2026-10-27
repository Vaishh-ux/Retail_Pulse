# Store catalogue and stockout simulator ---------------------------------------------------
# A catalogue of the USER's own products (names, prices, stock, lead times). It is kept
# completely separate from FreshRetailNet-50K, which only has encoded product IDs and
# normalised sales. A catalogue row is linked to a research product only when the user
# sets `linked_product_id` explicitly.
#
# Everything here is pure R (no Shiny) so it can be unit-tested.

INV_COLS <- c("sku", "name", "category", "price", "stock", "reorder_level", "lead_time_days", "expiry_date", "linked_product_id")
INV_REQUIRED <- c("sku", "name", "stock")
INV_LABELS <- c(sku = "SKU", name = "Product name", category = "Category", price = "Price", stock = "Stock on hand",
                reorder_level = "Reorder level", lead_time_days = "Lead time (days)", expiry_date = "Expiry date",
                linked_product_id = "Linked research product")
INV_MAX_ROWS <- 2000

inv_empty <- function() {
  data.frame(sku = character(), name = character(), category = character(), price = numeric(), stock = numeric(),
             reorder_level = numeric(), lead_time_days = numeric(), expiry_date = character(),
             linked_product_id = integer(), source = character(), updated = character(), stringsAsFactors = FALSE)
}

# Blank template users can fill in (one example row, clearly marked)
inv_template <- function() {
  data.frame(sku = "EXAMPLE-001", name = "Example: whole milk 1 L (replace this row)", category = "Dairy", price = 1.20,
             stock = 24, reorder_level = 10, lead_time_days = 2, expiry_date = "2026-11-05", linked_product_id = "",
             stringsAsFactors = FALSE)
}

# Small, clearly fictional demonstration catalogue. Not real store data; not linked to
# FreshRetailNet-50K products (the research data has no product names).
inv_sample <- function(today = Sys.Date()) {
  d <- function(n) format(today + n, "%Y-%m-%d")
  x <- data.frame(
    sku = sprintf("SAMPLE-%03d", 1:8),
    name = c("Whole milk 1 L", "Sourdough loaf", "Bananas (per kg)", "Free-range eggs (6)", "Greek yoghurt 500 g",
             "Baby spinach 200 g", "Cheddar 400 g", "Orange juice 1 L"),
    category = c("Dairy", "Bakery", "Fruit & veg", "Dairy", "Dairy", "Fruit & veg", "Dairy", "Drinks"),
    price = c(1.20, 3.50, 1.10, 2.40, 2.10, 1.80, 4.20, 2.60),
    stock = c(14, 6, 22, 30, 4, 9, 18, 0),
    reorder_level = c(12, 8, 10, 12, 6, 6, 6, 8),
    lead_time_days = c(1, 1, 2, 3, 2, 1, 5, 4),
    expiry_date = c(d(4), d(2), d(5), d(14), d(9), d(3), d(40), d(20)),
    linked_product_id = NA_integer_, stringsAsFactors = FALSE)
  x$source <- "sample"; x$updated <- format(Sys.time(), "%Y-%m-%d %H:%M")
  x
}

.trim <- function(x) { x <- trimws(as.character(x)); x[is.na(x)] <- ""; x }
.num <- function(x) suppressWarnings(as.numeric(gsub(",", "", .trim(x))))

# Parse a research-product reference: "108", "P108", " p108 " -> 108L; "" -> NA
inv_parse_pid <- function(x) {
  x <- toupper(.trim(x)); x <- sub("^P", "", x)
  out <- suppressWarnings(as.integer(x)); out[!nzchar(x)] <- NA_integer_
  out
}

# Validate one or more candidate records (a data frame of character columns, as read from
# a CSV or a form). Returns the cleaned typed rows plus a per-row list of error messages.
#   existing_skus: SKUs already in the catalogue (to detect duplicates)
#   valid_pids:    research product IDs that may be linked
inv_validate <- function(df, existing_skus = character(), valid_pids = integer()) {
  df <- as.data.frame(df, stringsAsFactors = FALSE)
  names(df) <- tolower(gsub("[^a-z0-9]+", "_", tolower(trimws(names(df)))))
  names(df) <- sub("^_|_$", "", names(df))
  alias <- c(product_id = "sku", id = "sku", product_name = "name", qty = "stock", quantity = "stock", stock_quantity = "stock",
             current_stock = "stock", min_stock = "reorder_level", reorder_threshold = "reorder_level", lead_time = "lead_time_days",
             expiry = "expiry_date", linked_product = "linked_product_id")
  for (a in names(alias)) if (a %in% names(df) && !alias[[a]] %in% names(df)) names(df)[names(df) == a] <- alias[[a]]
  missing_cols <- setdiff(INV_REQUIRED, names(df))
  if (length(missing_cols))
    return(list(ok = FALSE, file_error = sprintf("Missing required column(s): %s. Download the template to see the expected columns.",
                                                 paste(INV_LABELS[missing_cols], collapse = ", ")), rows = NULL, errors = list()))
  if (nrow(df) > INV_MAX_ROWS) return(list(ok = FALSE, file_error = sprintf("The file has %d rows; the limit is %d.", nrow(df), INV_MAX_ROWS), rows = NULL, errors = list()))
  if (!nrow(df)) return(list(ok = FALSE, file_error = "The file has no data rows.", rows = NULL, errors = list()))
  for (c in setdiff(INV_COLS, names(df))) df[[c]] <- ""
  ignored <- setdiff(names(df), c(INV_COLS, "source", "updated"))
  n <- nrow(df)
  sku <- .trim(df$sku); name <- .trim(df$name); category <- .trim(df$category)
  price <- .num(df$price); stock <- .num(df$stock); reorder <- .num(df$reorder_level); lead <- .num(df$lead_time_days)
  exp_raw <- .trim(df$expiry_date); exp <- suppressWarnings(as.Date(exp_raw, format = "%Y-%m-%d"))
  pid <- inv_parse_pid(df$linked_product_id); pid_raw <- .trim(df$linked_product_id)
  errs <- vector("list", n)
  key <- toupper(sku)
  dup_in_file <- duplicated(key) & nzchar(key)
  for (i in seq_len(n)) {
    e <- character()
    if (!nzchar(sku[i])) e <- c(e, "SKU is missing")
    else if (nchar(sku[i]) > 40) e <- c(e, "SKU is longer than 40 characters")
    if (dup_in_file[i]) e <- c(e, sprintf("SKU %s appears more than once in this file", sku[i]))
    if (!nzchar(name[i])) e <- c(e, "Product name is missing")
    else if (nchar(name[i]) > 80) e <- c(e, "Product name is longer than 80 characters")
    if (!nzchar(.trim(df$stock)[i])) e <- c(e, "Stock on hand is missing")
    else if (is.na(stock[i])) e <- c(e, sprintf("Stock on hand '%s' is not a number", .trim(df$stock)[i]))
    else if (stock[i] < 0) e <- c(e, "Stock on hand cannot be negative")
    else if (stock[i] != round(stock[i])) e <- c(e, "Stock on hand must be a whole number")
    if (nzchar(.trim(df$price)[i]) && (is.na(price[i]) || price[i] < 0)) e <- c(e, sprintf("Price '%s' must be a number of 0 or more", .trim(df$price)[i]))
    if (nzchar(.trim(df$reorder_level)[i]) && (is.na(reorder[i]) || reorder[i] < 0)) e <- c(e, sprintf("Reorder level '%s' must be a number of 0 or more", .trim(df$reorder_level)[i]))
    if (nzchar(.trim(df$lead_time_days)[i]) && (is.na(lead[i]) || lead[i] < 0 || lead[i] > 365 || lead[i] != round(lead[i])))
      e <- c(e, sprintf("Lead time '%s' must be a whole number of days between 0 and 365", .trim(df$lead_time_days)[i]))
    if (nzchar(exp_raw[i]) && is.na(exp[i])) e <- c(e, sprintf("Expiry date '%s' must look like 2026-11-30", exp_raw[i]))
    if (nzchar(pid_raw[i]) && (is.na(pid[i]) || (length(valid_pids) && !pid[i] %in% valid_pids)))
      e <- c(e, sprintf("Linked research product '%s' does not exist in this store's data", pid_raw[i]))
    errs[[i]] <- e
  }
  rows <- data.frame(sku = sku, name = name, category = category, price = price, stock = stock,
                     reorder_level = ifelse(is.na(reorder), 0, reorder), lead_time_days = lead,
                     expiry_date = ifelse(is.na(exp), NA_character_, format(exp, "%Y-%m-%d")),
                     linked_product_id = pid, stringsAsFactors = FALSE)
  list(ok = TRUE, file_error = NULL, rows = rows, errors = errs, ignored_columns = ignored,
       duplicate_existing = toupper(sku) %in% toupper(existing_skus) & nzchar(sku))
}

# Merge validated rows into a catalogue. Duplicates of existing SKUs are skipped unless
# on_duplicate = "update". Invalid rows are never added. Returns the new catalogue and counts.
inv_merge <- function(catalogue, v, on_duplicate = c("skip", "update"), source = "import") {
  on_duplicate <- match.arg(on_duplicate)
  stopifnot(isTRUE(v$ok))
  valid <- lengths(v$errors) == 0
  rows <- v$rows; rows$source <- source; rows$updated <- format(Sys.time(), "%Y-%m-%d %H:%M")
  dup <- v$duplicate_existing
  add <- rows[valid & !dup, , drop = FALSE]
  upd <- rows[valid & dup, , drop = FALSE]
  out <- catalogue
  n_upd <- 0L
  if (on_duplicate == "update" && nrow(upd)) {
    idx <- match(toupper(upd$sku), toupper(out$sku))
    for (k in seq_len(nrow(upd))) { out[idx[k], names(upd)] <- upd[k, ]; n_upd <- n_upd + 1L }
  }
  out <- rbind(out, add[, names(out), drop = FALSE])
  list(catalogue = out, added = nrow(add), updated = n_upd, skipped_duplicates = if (on_duplicate == "skip") nrow(upd) else 0L,
       rejected = sum(!valid))
}

# Status shown in the catalogue (based only on the user's own numbers)
inv_status <- function(cat, today = Sys.Date(), expiry_days = 3) {
  if (!nrow(cat)) return(character())
  exp <- as.Date(cat$expiry_date)
  dplyr::case_when(
    cat$stock <= 0 ~ "Out of stock",
    !is.na(exp) & exp < today ~ "Expired",
    cat$stock <= cat$reorder_level ~ "At or below reorder level",
    !is.na(exp) & exp <= today + expiry_days ~ "Expires soon",
    TRUE ~ "OK")
}

# Expired or expiring within `days` (independent of the stock status shown per row)
inv_expiring <- function(cat, today = Sys.Date(), days = 3) {
  if (!nrow(cat)) return(logical())
  exp <- suppressWarnings(as.Date(cat$expiry_date))
  !is.na(exp) & exp <= today + days
}

# Day-by-day demand for the simulator.
#   base: expected units per day (user input), multiplier: e.g. 1.2 = +20%
#   pattern: optional numeric vector of relative weekday weights (mean 1), recycled
inv_demand_path <- function(base, horizon, multiplier = 1, pattern = NULL) {
  base <- max(0, as.numeric(base)); horizon <- max(1L, as.integer(horizon))
  w <- if (length(pattern) && all(is.finite(pattern)) && mean(pattern) > 0) rep_len(pattern / mean(pattern), horizon) else rep(1, horizon)
  base * multiplier * w
}

# Project stock forward with NO incoming delivery inside the horizon except the one that
# would arrive after `lead + delay` days if ordered today (its quantity is not modelled:
# RetailPulse never suggests order quantities). Returns key figures for the comparison.
inv_simulate <- function(stock, demand, lead = 0, delay = 0, safety = 0) {
  stock <- as.numeric(stock); demand <- pmax(0, as.numeric(demand)); h <- length(demand)
  if (!is.finite(stock) || stock < 0) stop("stock must be a number of 0 or more")
  arrive <- max(0, as.numeric(lead) + as.numeric(delay))
  cum <- cumsum(demand)
  level <- pmax(0, stock - cum)
  unmet <- pmax(0, cum - stock)
  # fractional days until stock runs out (linear within a day); Inf if it lasts beyond the horizon
  days_left <- if (stock <= 0) 0 else {
    k <- which(cum >= stock)[1]
    if (is.na(k)) Inf else (k - 1) + (stock - c(0, cum)[k]) / demand[k]
  }
  below <- if (stock < safety) 0L else which(level < safety)[1]
  at_arrival <- if (arrive <= 0) stock else if (arrive <= h) level[ceiling(arrive)] else NA_real_
  list(path = data.frame(day = 0:h, stock = c(stock, level), demand = c(0, demand), unmet = c(0, unmet)),
       days_left = days_left, stockout_day = if (is.finite(days_left)) ceiling(max(days_left, 0)) else NA_integer_,
       below_safety_day = if (is.na(below)) NA_integer_ else below, arrival_day = arrive, stock_at_arrival = at_arrival,
       runs_out_before_arrival = is.finite(days_left) && days_left < arrive,
       unmet_before_arrival = if (arrive <= 0) 0 else unmet[min(h, ceiling(arrive))],
       total_demand = sum(demand), horizon = h)
}

# Catalogue as JSON for browser storage, and back (tolerant of bad input)
inv_to_json <- function(cat) jsonlite::toJSON(list(version = 1L, saved = format(Sys.time(), "%Y-%m-%d %H:%M"), rows = cat),
                                              dataframe = "rows", na = "null", auto_unbox = TRUE, digits = NA)
inv_from_json <- function(txt) {
  out <- tryCatch({
    x <- jsonlite::fromJSON(txt, simplifyDataFrame = TRUE)
    r <- x$rows
    if (is.null(r) || !length(r) || !NROW(r)) inv_empty() else {
      r <- as.data.frame(r, stringsAsFactors = FALSE)
      e <- inv_empty()
      for (c in names(e)) if (!c %in% names(r)) r[[c]] <- if (is.numeric(e[[c]])) NA_real_ else NA_character_
      r <- r[, names(e)]
      r$price <- as.numeric(r$price); r$stock <- as.numeric(r$stock); r$reorder_level <- as.numeric(r$reorder_level)
      r$lead_time_days <- as.numeric(r$lead_time_days); r$linked_product_id <- as.integer(r$linked_product_id)
      r$expiry_date <- as.character(r$expiry_date)
      r[!is.na(r$sku) & nzchar(r$sku) & is.finite(r$stock) & r$stock >= 0, , drop = FALSE]
    }
  }, error = function(e) NULL)
  out
}
