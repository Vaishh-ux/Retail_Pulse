# App bundle -----------------------------------------------------------------------
# One compact file per store for the web app, readable with base R (keeps `arrow` out
# of the server process). Only the tables the app displays are included: the full
# hourly matrix (~12 MB in memory) and the hourly replay stay in outputs/*.parquet.
# gzip is used because it reads ~9x faster than xz on a small CPU.
RP_BUNDLE_EXCLUDE <- c("hourly", "replay", "latent_validation_rows_full")

rp_write_bundle <- function(out_dir) {
  bundle <- list()
  for (f in list.files(out_dir, pattern = "\\.parquet$", full.names = TRUE)) {
    n <- sub("\\.parquet$", "", basename(f))
    if (n %in% RP_BUNDLE_EXCLUDE) next
    bundle[[n]] <- tibble::as_tibble(arrow::read_parquet(f))
  }
  for (n in c("manifest", "quality", "latent_validation"))
    bundle[[paste0("json_", n)]] <- jsonlite::read_json(file.path(out_dir, paste0(n, ".json")), simplifyVector = TRUE)
  f <- file.path(out_dir, "app_bundle.rds")
  saveRDS(bundle, f, compress = "gzip")
  invisible(f)
}
