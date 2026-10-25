# RetailPulse configuration --------------------------------------------------
# All settings can be overridden with environment variables (see .env.example).
# Thresholds below are design choices, documented in README.md ("Decision rules").

rp_env <- function(name, default) {
  v <- Sys.getenv(name, unset = NA_character_)
  if (is.na(v) || !nzchar(v)) default else v
}

rp_root <- function() {
  r <- rp_env("RP_ROOT", NA_character_)
  if (!is.na(r)) return(normalizePath(r, mustWork = FALSE))
  # walk up from the working directory until the project marker is found
  d <- normalizePath(getwd())
  for (i in 1:5) {
    if (file.exists(file.path(d, "environment.yml"))) return(d)
    d <- dirname(d)
  }
  normalizePath(getwd())
}

rp_config <- function() {
  root <- rp_root()
  list(
    root            = root,
    data_mode       = rp_env("RP_DATA_MODE", "auto"),          # auto | real | synthetic
    allow_download  = tolower(rp_env("RP_ALLOW_DOWNLOAD", "true")) == "true",
    store_id        = rp_env("RP_STORE_ID", "auto"),           # "auto" or an integer id
    raw_dir         = rp_env("RP_RAW_DIR", file.path(root, "data", "raw")),
    out_dir         = rp_env("RP_OUTPUT_DIR", file.path(root, "outputs")),
    seed            = as.integer(rp_env("RP_SEED", "2026")),
    # Trading hours used by the dataset's stock_hour6_22_cnt field: 06:00-21:59,
    # i.e. 0-based hours 6..21 -> 1-based list positions 7..22 (16 hours).
    trading_idx     = 7:22,
    stockout_day_h  = as.numeric(rp_env("RP_STOCKOUT_DAY_HOURS", "8")),   # "stockout day" flag
    risk_event_h    = as.numeric(rp_env("RP_RISK_EVENT_HOURS", "4")),     # target of risk model
    anomaly_z       = as.numeric(rp_env("RP_ANOMALY_Z", "3")),
    baseline_window = 28L,
    min_share_in    = 0.25,   # below this in-stock share, latent demand uses the fallback level
    horizon         = 7L,     # evaluated horizon (length of the dataset's eval split)
    horizon_max     = 14L     # longest horizon offered in the app (beyond 7 days = not evaluated)
  )
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a))) b else a
