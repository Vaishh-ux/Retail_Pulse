# Load pipeline outputs once at start-up -------------------------------------------
# The app never computes models; it reads the artifacts written by
# pipeline/run_pipeline.R. If they are missing, the app shows a clear error page.

rp_app_root <- function() {
  r <- Sys.getenv("RP_ROOT", unset = NA)
  if (!is.na(r) && nzchar(r)) return(normalizePath(r))
  for (cand in c(".", "..", "../..")) if (file.exists(file.path(cand, "environment.yml"))) return(normalizePath(cand))
  normalizePath(".")
}

rp_load_outputs <- function(out_dir) {
  need <- c("manifest.json", "daily.parquet", "products.parquet", "recommendations.parquet")
  missing <- need[!file.exists(file.path(out_dir, need))]
  if (length(missing)) return(list(ok = FALSE, missing = missing, out_dir = out_dir))
  bf <- file.path(out_dir, "app_bundle.rds")
  bundle <- if (file.exists(bf)) readRDS(bf) else NULL      # preferred: no arrow needed
  pq <- function(n) {
    if (!is.null(bundle)) return(if (!is.null(bundle[[n]])) bundle[[n]] else tibble::tibble())
    f <- file.path(out_dir, paste0(n, ".parquet"))
    if (file.exists(f)) tibble::as_tibble(arrow::read_parquet(f)) else tibble::tibble()
  }
  js <- function(n) {
    if (!is.null(bundle) && !is.null(bundle[[paste0("json_", n)]])) return(bundle[[paste0("json_", n)]])
    f <- file.path(out_dir, paste0(n, ".json"))
    if (file.exists(f)) jsonlite::read_json(f, simplifyVector = TRUE) else list()
  }
  o <- list(ok = TRUE, out_dir = out_dir)
  for (n in c("daily", "hourly", "weekday_hour", "store_weekday_hour", "instock_vs_out", "variability",
              "store_daily", "products", "latent_validation_rows", "latent_validation_by_cutoff",
              "forecast_cv_overall", "forecast_cv_product", "forecast_eval", "forecast_eval_overall",
              "forecast_eval_product", "forecast_next", "ets_spec", "anomalies", "sustained_runs",
              "risk_coefficients", "risk_calibration", "risk_metrics", "risk_next", "sellout_curves",
              "sellout_summary", "replay", "alerts", "promo_effects", "indicators", "recommendations",
              "feature_dictionary", "store_summary")) o[[n]] <- pq(n)
  o$manifest <- js("manifest"); o$quality <- js("quality"); o$latent_val <- js("latent_validation")
  o$daily$dt <- as.Date(o$daily$dt)
  o$products <- o$products[order(o$products$product_id), ]
  o$product_choices <- stats::setNames(o$products$product_id,
                                       sprintf("%s · %s", o$products$label, o$products$category))
  o$label_of <- stats::setNames(o$products$label, o$products$product_id)
  o
}

# Stores with precomputed results: outputs/ (default store) plus outputs/stores/<id>/.
# Returns a named character vector: names = store id, values = output directory.
rp_store_dirs <- function(out_dir) {
  dirs <- c(out_dir, list.dirs(file.path(out_dir, "stores"), recursive = FALSE))
  dirs <- dirs[file.exists(file.path(dirs, "manifest.json"))]
  ids <- vapply(dirs, function(d) as.character(jsonlite::read_json(file.path(d, "manifest.json"))$store_id %||% NA), "")
  keep <- !is.na(ids) & !duplicated(ids)
  stats::setNames(unname(dirs[keep]), ids[keep])
}

# Lazily loaded, cached per process (each store is ~20 MB in memory)
.rp_cache <- new.env(parent = emptyenv())
rp_get_store <- function(dirs, sid) {
  sid <- as.character(sid)
  if (!length(sid) || is.na(sid) || !sid %in% names(dirs)) sid <- names(dirs)[1]
  if (is.null(.rp_cache[[sid]])) {
    # keep at most RP_STORE_CACHE stores in memory (default 2) to fit small instances
    max_n <- suppressWarnings(as.integer(Sys.getenv("RP_STORE_CACHE", "2"))); if (is.na(max_n) || max_n < 1) max_n <- 2
    loaded <- setdiff(ls(.rp_cache), ".order")
    if (length(loaded) >= max_n) {
      drop <- utils::head(setdiff(.rp_cache$.order %||% loaded, sid), length(loaded) - max_n + 1)
      for (k in drop) rm(list = k, envir = .rp_cache)
      .rp_cache$.order <- setdiff(.rp_cache$.order, drop)
      gc(verbose = FALSE)
    }
    .rp_cache[[sid]] <- rp_load_outputs(dirs[[sid]])
  }
  .rp_cache$.order <- c(setdiff(.rp_cache$.order, sid), sid)
  .rp_cache[[sid]]
}

fmt_num <- function(x, d = 1) ifelse(is.na(x), "–", formatC(x, format = "f", digits = d, big.mark = ","))
fmt_pct <- function(x, d = 0) ifelse(is.na(x), "–", paste0(formatC(100 * x, format = "f", digits = d), "%"))
plabel <- function(id) paste0("P", id)
