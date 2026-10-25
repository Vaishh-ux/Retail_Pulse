#!/usr/bin/env sh
# Rebuild the static dashboard from the R results (run after pipeline/run_pipeline.R).
set -e
cd "$(dirname "$0")/.."
Rscript scripts/knit_reports.R
Rscript scripts/export_static.R
node tests/static/parity.test.js
echo "site/ is ready: serve it with  cd site && python3 -m http.server 8080"
