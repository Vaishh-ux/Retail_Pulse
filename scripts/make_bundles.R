# Rebuild outputs/app_bundle.rds (and outputs/stores/<id>/app_bundle.rds) from the
# pipeline's parquet/json outputs, without re-running the analysis.
root <- normalizePath(Sys.getenv("RP_ROOT", unset = "."))
source(file.path(root, "R", "bundle.R"))
out <- file.path(root, "outputs")
for (d in c(out, list.dirs(file.path(out, "stores"), recursive = FALSE)))
  if (file.exists(file.path(d, "manifest.json"))) message("bundle: ", rp_write_bundle(d), sprintf(" (%.1f MB)", file.size(file.path(d, "app_bundle.rds")) / 1e6))
