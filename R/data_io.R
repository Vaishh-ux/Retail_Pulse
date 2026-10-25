# Data access -----------------------------------------------------------------
# Real data: FreshRetailNet-50K Parquet files (Dingdong-Inc, CC BY 4.0) placed in
# data/raw/. File names containing "train" or "eval" set the split. The function
# rp_download_real() fetches them via the Hugging Face datasets-server API (used
# during the Render build, where Hugging Face is reachable).

RP_SCHEMA <- c("city_id", "store_id", "management_group_id", "first_category_id",
               "second_category_id", "third_category_id", "product_id", "dt",
               "sale_amount", "hours_sale", "stock_hour6_22_cnt", "hours_stock_status",
               "discount", "holiday_flag", "activity_flag", "precpt",
               "avg_temperature", "avg_humidity", "avg_wind_level")

rp_real_files <- function(cfg) {
  f <- list.files(cfg$raw_dir, pattern = "\\.parquet$", full.names = TRUE, recursive = TRUE)
  f[grepl("train|eval", basename(f), ignore.case = TRUE)]
}

rp_split_of <- function(path) ifelse(grepl("eval", basename(path), ignore.case = TRUE), "eval", "train")

rp_download_real <- function(cfg, dataset = "Dingdong-Inc/FreshRetailNet-50K") {
  dir.create(cfg$raw_dir, recursive = TRUE, showWarnings = FALSE)
  api <- paste0("https://datasets-server.huggingface.co/parquet?dataset=", utils::URLencode(dataset, reserved = TRUE))
  info <- tryCatch(jsonlite::fromJSON(api), error = function(e) NULL)
  if (is.null(info) || is.null(info$parquet_files) || NROW(info$parquet_files) == 0) {
    message("[data] datasets-server lookup failed: ", api)
    return(character(0))
  }
  pf <- info$parquet_files
  pf <- pf[pf$split %in% c("train", "eval"), , drop = FALSE]
  got <- character(0)
  for (i in seq_len(nrow(pf))) {
    dest <- file.path(cfg$raw_dir, sprintf("%s-%02d.parquet", pf$split[i], i))
    ok <- tryCatch({
      utils::download.file(pf$url[i], dest, mode = "wb", quiet = TRUE)
      TRUE
    }, error = function(e) { message("[data] download failed: ", pf$url[i]); FALSE })
    if (ok && file.exists(dest) && file.size(dest) > 1000) got <- c(got, dest)
  }
  got
}

# List-columns of length-24 vectors -> numeric matrix (rows x 24)
rp_list_to_matrix <- function(x) {
  if (inherits(x, "arrow_list") || inherits(x, "vctrs_list_of")) x <- as.list(x)
  m <- matrix(NA_real_, nrow = length(x), ncol = 24)
  len <- lengths(x)
  ok <- which(len == 24)
  if (length(ok)) m[ok, ] <- matrix(as.numeric(unlist(x[ok], use.names = FALSE)), ncol = 24, byrow = TRUE)
  attr(m, "bad_length") <- which(len != 24)
  m
}

# Summaries used to choose a representative store (real data only)
rp_store_summary <- function(files) {
  ds <- arrow::open_dataset(files[rp_split_of(files) == "train"])
  ds |>
    dplyr::group_by(store_id) |>
    dplyr::summarise(n_products = dplyr::n_distinct(product_id), n_rows = dplyr::n(),
                     stockout_hours = sum(stock_hour6_22_cnt, na.rm = TRUE)) |>
    dplyr::collect() |>
    dplyr::mutate(stockout_hour_rate = stockout_hours / (n_rows * 16))
}

rp_pick_store <- function(summary) {
  # Representative = many products and a stockout rate that is neither negligible
  # nor extreme. Ties broken by product count.
  cand <- summary[summary$stockout_hour_rate >= 0.05 & summary$stockout_hour_rate <= 0.35, ]
  if (!nrow(cand)) cand <- summary
  cand <- cand[order(-cand$n_products, abs(cand$stockout_hour_rate - 0.15)), ]
  cand$store_id[1]
}

# Load one store (both splits) as a tibble with the dataset's schema + split
rp_load_store <- function(cfg, mode) {
  if (mode == "synthetic") {
    all <- rp_make_synthetic(seed = cfg$seed)
    sid <- if (cfg$store_id == "auto") 0L else as.integer(cfg$store_id)
    return(list(data = all[all$store_id == sid, ], store_id = sid, store_summary = NULL))
  }
  files <- rp_real_files(cfg)
  ssum <- rp_store_summary(files)
  sid <- if (cfg$store_id == "auto") rp_pick_store(ssum) else as.integer(cfg$store_id)
  parts <- lapply(files, function(f) {
    arrow::open_dataset(f) |>
      dplyr::filter(store_id == sid) |>
      dplyr::collect() |>
      dplyr::mutate(split = rp_split_of(f))
  })
  d <- dplyr::bind_rows(parts)
  missing_cols <- setdiff(RP_SCHEMA, names(d))
  if (length(missing_cols)) stop("Real data is missing expected columns: ", paste(missing_cols, collapse = ", "))
  list(data = d, store_id = sid, store_summary = ssum)
}

rp_resolve_mode <- function(cfg) {
  if (cfg$data_mode == "synthetic") return("synthetic")
  have <- length(rp_real_files(cfg)) > 0
  if (!have && cfg$allow_download && cfg$data_mode %in% c("auto", "real")) {
    message("[data] no real files found; trying to download FreshRetailNet-50K ...")
    have <- length(rp_download_real(cfg)) > 0
  }
  if (have) return("real")
  if (cfg$data_mode == "real") stop("RP_DATA_MODE=real but no FreshRetailNet-50K Parquet files are available in ", cfg$raw_dir)
  message("[data] real data unavailable -> SYNTHETIC DEMO MODE")
  "synthetic"
}
