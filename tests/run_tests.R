#!/usr/bin/env Rscript
# Runs all R tests. Usage: Rscript tests/run_tests.R
args <- commandArgs(FALSE)
here <- dirname(normalizePath(sub("--file=", "", grep("--file=", args, value = TRUE)[1])))
Sys.setenv(NOT_CRAN = "true")
res <- testthat::test_dir(file.path(here, "testthat"), reporter = testthat::ProgressReporter$new(show_praise = FALSE),
                          stop_on_failure = FALSE)
df <- as.data.frame(res)
cat(sprintf("\nTests: %d expectations passed, %d failed, %d skipped, %d errors\n",
            sum(df$passed), sum(df$failed), sum(df$skipped), sum(df$error)))
quit(status = if (sum(df$failed) + sum(df$error) > 0) 1 else 0)
