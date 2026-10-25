# Knit report/report.Rmd once per shipped store:
#   outputs/              -> app/www/report.html and app/www/reports/report_<id>.html
#   outputs/stores/<id>/  -> app/www/reports/report_<id>.html
root <- normalizePath(Sys.getenv("RP_ROOT", unset = "."))
out <- file.path(root, "outputs")
dirs <- c(out, list.dirs(file.path(out, "stores"), recursive = FALSE))
dirs <- dirs[file.exists(file.path(dirs, "manifest.json")) & file.exists(file.path(dirs, "daily.parquet"))]
www <- file.path(root, "app", "www"); dir.create(file.path(www, "reports"), recursive = TRUE, showWarnings = FALSE)
for (i in seq_along(dirs)) {
  sid <- jsonlite::read_json(file.path(dirs[i], "manifest.json"))$store_id
  Sys.setenv(RP_OUTPUT_DIR = dirs[i], RP_ROOT = root)
  f <- rmarkdown::render(file.path(root, "report", "report.Rmd"), output_dir = file.path(www, "reports"),
                         output_file = sprintf("report_%s.html", sid), intermediates_dir = tempdir(), quiet = TRUE, envir = new.env())
  if (i == 1) file.copy(f, file.path(www, "report.html"), overwrite = TRUE)
  message("report for store ", sid, ": ", f)
}
