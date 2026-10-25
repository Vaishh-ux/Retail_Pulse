# RetailPulse - single Docker web service for Render
# R 4.4 and all packages come from conda-forge (pinned in environment.yml), so
# the build does not depend on CRAN or compile packages from source.
FROM mambaorg/micromamba:2.0.5

USER root
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8 MAMBA_DOCKERFILE_ACTIVATE=1 \
    RP_ROOT=/app PATH=/opt/conda/bin:$PATH

COPY environment.yml /tmp/environment.yml
RUN micromamba install -y -n base -f /tmp/environment.yml && micromamba clean --all --yes

WORKDIR /app
COPY . /app

# The repository ships the analysis results computed from the real FreshRetailNet-50K
# files (outputs/ for store 18 and outputs/stores/<id>/ for extra stores, ~15 MB), so
# the build does not need the 115 MB dataset. The R Markdown report is knitted here,
# once per store. Set RP_REBUILD=true to re-run the whole pipeline during the build
# instead (it then uses data/raw/*.parquet, or downloads from Hugging Face, or - if
# both fail - falls back to clearly labelled synthetic demo data).
ARG RP_REBUILD=false
ARG RP_DATA_MODE=auto
ARG RP_STORE_ID=auto
ARG RP_EXTRA_STORES="235 263"
ENV RP_DATA_MODE=${RP_DATA_MODE} RP_STORE_ID=${RP_STORE_ID}
RUN if [ "$RP_REBUILD" = "true" ] || [ ! -f outputs/manifest.json ]; then \
      Rscript pipeline/run_pipeline.R && \
      if [ "$(grep -o '"mode": "[a-z]*"' outputs/manifest.json)" = '"mode": "real"' ]; then \
        for s in $RP_EXTRA_STORES; do RP_STORE_ID=$s RP_OUTPUT_DIR=/app/outputs/stores/$s Rscript pipeline/run_pipeline.R; done; \
      else rm -rf outputs/stores; fi; \
    else echo "Using precomputed outputs: $(grep -o '"mode": "[a-z]*"' outputs/manifest.json)"; fi \
 && Rscript scripts/knit_reports.R \
 && rm -rf data/raw/*.parquet

# Render provides PORT; app/run.R binds to 0.0.0.0:$PORT
ENV PORT=10000
EXPOSE 10000
CMD ["Rscript", "app/run.R"]
