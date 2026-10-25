# RetailPulse - Demand Monitoring and Early Warning for Small Retailers
# Shiny application. Reads precomputed results from outputs/ (see pipeline/run_pipeline.R).
# Several stores can be shipped (outputs/ + outputs/stores/<id>/); the store is chosen
# with ?store=<id> in the URL or the navbar selector.

suppressPackageStartupMessages({
  library(shiny); library(bslib); library(plotly); library(reactable)
})

ROOT <- rp_app_root()
for (f in list.files(file.path(ROOT, "R"), pattern = "\\.R$", full.names = TRUE)) source(f, local = FALSE)
OUT_DIR <- Sys.getenv("RP_OUTPUT_DIR", unset = file.path(ROOT, "outputs"))
STORE_DIRS <- rp_store_dirs(OUT_DIR)
WWW <- file.path(ROOT, "app", "www")

store_from_query <- function(qs) {
  q <- shiny::parseQueryString(qs %||% "")
  q$store %||% names(STORE_DIRS)[1]
}
report_file <- function(sid) {
  per_store <- file.path("reports", sprintf("report_%s.html", sid))
  if (file.exists(file.path(WWW, per_store))) return(per_store)
  if (identical(as.character(sid), names(STORE_DIRS)[1]) && file.exists(file.path(WWW, "report.html"))) return("report.html")
  NULL
}

fatal_ui <- function(RP) bslib::page_fillable(theme = rp_theme(), htmltools::div(class = "rp-fatal",
  htmltools::h2("RetailPulse results not found"),
  htmltools::p("The analytical pipeline has not produced its outputs yet. Run:"),
  htmltools::pre("Rscript pipeline/run_pipeline.R"),
  htmltools::p("Missing files in ", htmltools::code(RP$out_dir %||% OUT_DIR), ": ", paste(RP$missing %||% "manifest.json", collapse = ", "))))

build_ui <- function(RP, sid) {
  m <- RP$manifest
  synthetic <- identical(m$mode, "synthetic")
  store_choices <- stats::setNames(names(STORE_DIRS), paste("Store", names(STORE_DIRS)))
  rep <- report_file(sid)

  brand <- htmltools::div(class = "rp-brand",
    htmltools::span(class = "rp-brand-mark", htmltools::tags$svg(width = 18, height = 18, viewBox = "0 0 24 24", `aria-hidden` = "true",
      htmltools::tags$path(d = "M2 13h4l3-8 4 14 3-6h6", fill = "none", stroke = "#D9A441", `stroke-width` = 2.4,
                           `stroke-linecap` = "round", `stroke-linejoin` = "round"))),
    htmltools::span("RetailPulse", htmltools::tags$small("Demand & stock intelligence")))

  bslib::page_navbar(
    id = "nav", title = brand, window_title = sprintf("RetailPulse · Store %s", m$store_id), theme = rp_theme(), fillable = FALSE,
    navbar_options = bslib::navbar_options(collapsible = TRUE, underline = FALSE, bg = RP_COL$forest, theme = "dark"),
    header = htmltools::tagList(
      htmltools::tags$head(htmltools::tags$link(rel = "stylesheet", href = "styles.css"),
                           htmltools::tags$link(rel = "icon", href = "favicon.svg", type = "image/svg+xml"),
                           htmltools::tags$meta(name = "description", content = "Demand monitoring and early warning for small retailers")),
      shiny::useBusyIndicators(spinners = TRUE, pulse = TRUE),
      if (synthetic) htmltools::div(class = "rp-demo-banner", shiny::icon("triangle-exclamation"), htmltools::div(htmltools::strong("Demo mode: synthetic data. "),
        "Every number below comes from a generated dataset with the FreshRetailNet-50K schema, so the app can be tested. They are not findings about real stores. ",
        "Add the real Parquet files and re-run the pipeline to replace them."))),
    bslib::nav_panel("Overview", value = "overview", icon = shiny::icon("gauge-high"),
                     mod_overview_ui("ov", RP)),
    bslib::nav_panel("Product", value = "product", icon = shiny::icon("magnifying-glass-chart"), mod_product_ui("pr", RP$product_choices)),
    bslib::nav_panel("Monitoring", value = "monitor", icon = shiny::icon("clock-rotate-left"), mod_monitor_ui("mo", RP$product_choices)),
    bslib::nav_panel("Forecast & Scenarios", value = "scenario", icon = shiny::icon("sliders"), mod_scenario_ui("sc", RP$product_choices)),
    bslib::nav_panel("Data & Methods", value = "methods", icon = shiny::icon("flask"), mod_methods_ui("me", RP$product_choices)),
    bslib::nav_panel("Report", value = "report", icon = shiny::icon("file-lines"), mod_report_ui("rep", RP, rep)),
    bslib::nav_spacer(),
    bslib::nav_item(htmltools::div(class = "rp-nav-store",
      htmltools::span(class = paste("rp-data-pill", if (synthetic) "synthetic" else "real"), htmltools::span(class = "dot"),
                      if (synthetic) "Synthetic demo data" else "Real data · FreshRetailNet-50K"),
      if (length(store_choices) > 1) shiny::selectInput("store", "Store", choices = store_choices, selected = sid, width = "130px", selectize = FALSE)
      else htmltools::span(class = "rp-data-pill real", sprintf("Store %s", m$store_id)))),
    footer = htmltools::div(class = "rp-footer",
      sprintf("RetailPulse · Store %s · %s to %s · Data: FreshRetailNet-50K (Dingdong-Inc, CC BY 4.0) · CSI3005 Advanced Data Visualization Techniques",
              m$store_id, m$date_min, m$date_max),
      if (synthetic) " · currently showing SYNTHETIC demo data")
  )
}

# Built pages are cached per store: building the UI (and compiling the theme's Sass)
# is the slowest part of a request, which matters on small instances.
.ui_cache <- new.env(parent = emptyenv())
cached_ui <- function(RP) {
  sid <- as.character(RP$manifest$store_id)
  if (is.null(.ui_cache[[sid]])) .ui_cache[[sid]] <- build_ui(RP, sid)
  .ui_cache[[sid]]
}

ui <- function(req) {
  if (!length(STORE_DIRS)) return(fatal_ui(list(out_dir = OUT_DIR)))
  sid <- store_from_query(req$QUERY_STRING)
  RP <- rp_get_store(STORE_DIRS, sid)
  if (!isTRUE(RP$ok)) return(fatal_ui(RP))
  cached_ui(RP)
}

# Warm up BEFORE the server starts listening: load the default store, build its page
# and compile the theme, so the first request (and the host's health check) is fast.
if (length(STORE_DIRS)) {
  t0 <- Sys.time()
  try({
    RP0 <- rp_get_store(STORE_DIRS, names(STORE_DIRS)[1])
    if (isTRUE(RP0$ok)) invisible(htmltools::renderTags(cached_ui(RP0)))
  }, silent = FALSE)
  message(sprintf("RetailPulse warm-up done in %.1f s", as.numeric(difftime(Sys.time(), t0, units = "secs"))))
}

server <- function(input, output, session) {
  if (!length(STORE_DIRS)) return()
  sid <- store_from_query(shiny::isolate(session$clientData$url_search))
  RP <- rp_get_store(STORE_DIRS, sid)
  if (!isTRUE(RP$ok)) return()
  sid <- as.character(RP$manifest$store_id)
  rain_q <- stats::quantile(RP$daily$precpt, 0.9, na.rm = TRUE)

  # switching store reloads the page with ?store=<id> so every module starts clean
  shiny::observeEvent(input$store, {
    if (!identical(as.character(input$store), sid)) {
      shiny::updateQueryString(paste0("?store=", input$store), mode = "replace")
      session$reload()
    }
  }, ignoreInit = TRUE)

  first <- RP$recommendations$product_id[1] %||% RP$products$product_id[1]
  state <- shiny::reactiveValues(product = first, date = NULL, zthr = RP$manifest$thresholds$anomaly_z, horizon = 7)

  anoms_r <- shiny::reactive(rp_classify_anomalies(RP$daily, state$zthr, rain_q))
  build_recs <- function(params, zthr, growth = 1) {
    an <- rp_classify_anomalies(RP$daily, zthr, rain_q)
    ind <- rp_product_indicators(RP$daily, RP$forecast_next, RP$manifest$chosen_model, an, RP$risk_next,
                                 RP$forecast_cv_product, RP$products[, c("product_id", "full_instock_days", "zero_sale_share")],
                                 growth = growth)
    rp_recommend(ind, params, risk_threshold = RP$manifest$risk_threshold)
  }
  recs_r <- shiny::reactive(build_recs(list(), state$zthr))

  goto_product <- function(pid, date = NULL) {
    state$product <- as.integer(pid)
    state$date <- if (!is.null(date)) as.Date(date) else NULL
    bslib::nav_select("nav", "product", session = session)
  }
  goto_page <- function(page) bslib::nav_select("nav", page, session = session)

  mod_overview_server("ov", RP, state, anoms_r, recs_r, goto_product, goto_page)
  mod_product_server("pr", RP, state, anoms_r, recs_r)
  mod_monitor_server("mo", RP, state, anoms_r, goto_product)
  mod_scenario_server("sc", RP, state, build_recs)
  mod_methods_server("me", RP, state)
  mod_report_server("rep", RP, state, recs_r, anoms_r)
}

shiny::shinyApp(ui, server)
