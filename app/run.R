#!/usr/bin/env Rscript
# Production entry point (used by the Docker image on Render).
# Binds to 0.0.0.0 and the PORT environment variable that Render provides.
port <- as.integer(Sys.getenv("PORT", "3838"))
here <- dirname(normalizePath(sub("--file=", "", grep("--file=", commandArgs(FALSE), value = TRUE)[1])))
Sys.setenv(RP_ROOT = Sys.getenv("RP_ROOT", unset = normalizePath(file.path(here, ".."))))
options(shiny.sanitize.errors = TRUE)
message(sprintf("RetailPulse starting on 0.0.0.0:%d (outputs: %s)", port, Sys.getenv("RP_OUTPUT_DIR", file.path(Sys.getenv("RP_ROOT"), "outputs"))))
shiny::runApp(here, host = "0.0.0.0", port = port, launch.browser = FALSE)
