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

fatal_ui <- function(RP) bslib::page_fillable(theme = rp_theme(), htmltools::div(class = "rp-fatal",
  htmltools::h2("RetailPulse results not found"),
  htmltools::p("The analytical pipeline has not produced its outputs yet. Run:"),
  htmltools::pre("Rscript pipeline/run_pipeline.R"),
  htmltools::p("Missing files in ", htmltools::code(RP$out_dir %||% OUT_DIR), ": ", paste(RP$missing %||% "manifest.json", collapse = ", "))))

build_ui <- function(RP, sid) {
  m <- RP$manifest
  synthetic <- identical(m$mode, "synthetic")
  store_choices <- stats::setNames(names(STORE_DIRS), paste("Store", names(STORE_DIRS)))

  brand <- htmltools::div(class = "rp-brand",
    htmltools::span(class = "rp-brand-mark", htmltools::tags$svg(width = 18, height = 18, viewBox = "0 0 24 24", `aria-hidden` = "true",
      htmltools::tags$path(d = "M2 13h4l3-8 4 14 3-6h6", fill = "none", stroke = "#D9A441", `stroke-width` = 2.4,
                           `stroke-linecap` = "round", `stroke-linejoin` = "round"))),
    htmltools::span("RetailPulse", htmltools::tags$small("Sales & demand for small shops")))

  bslib::page_navbar(
    id = "nav", title = brand, window_title = sprintf("RetailPulse · Store %s", m$store_id), theme = rp_theme(), fillable = FALSE,
    navbar_options = bslib::navbar_options(collapsible = TRUE, underline = FALSE, bg = RP_COL$forest, theme = "dark"),
    header = htmltools::tagList(
      htmltools::tags$head(htmltools::tags$link(rel = "stylesheet", href = "styles.css"),
                           htmltools::tags$script(src = "inventory.js", defer = NA),
                           htmltools::tags$link(rel = "icon", href = "favicon.svg", type = "image/svg+xml"),
                           htmltools::tags$meta(name = "description", content = "Demand monitoring and early warning for small retailers")),
      shiny::useBusyIndicators(spinners = TRUE, pulse = TRUE),
      if (synthetic) htmltools::div(class = "rp-demo-banner", shiny::icon("triangle-exclamation"), htmltools::div(htmltools::strong("Demo mode: synthetic data. "),
        "Every number below comes from a generated dataset with the FreshRetailNet-50K schema, so the app can be tested. They are not findings about real stores. ",
        "Add the real Parquet files and re-run the pipeline to replace them."))),
    bslib::nav_panel("Dashboard", value = "dashboard", icon = shiny::icon("gauge-high"), mod_dashboard_ui("db", RP)),
    bslib::nav_panel("Product Demand", value = "product", icon = shiny::icon("magnifying-glass-chart"), mod_product_ui("pr", RP$product_choices)),
    bslib::nav_panel("Data & Model Results", value = "results", icon = shiny::icon("flask"), mod_results_ui("rs", RP)),
    bslib::nav_panel("Inventory", value = "inventory", icon = shiny::icon("boxes-stacked"), mod_inventory_ui("inv")),
    bslib::nav_spacer(),
    bslib::nav_item(htmltools::div(class = "rp-nav-store",
      htmltools::span(class = paste("rp-data-pill", if (synthetic) "synthetic" else "real"), htmltools::span(class = "dot"),
                      if (synthetic) "Synthetic demo data" else "Real data · FreshRetailNet-50K"),
      if (length(store_choices) > 1) shiny::selectInput("store", "Store", choices = store_choices, selected = sid, width = "130px", selectize = FALSE)
      else htmltools::span(class = "rp-data-pill real", sprintf("Store %s", m$store_id)))),
    footer = htmltools::div(class = "rp-footer",
      sprintf("RetailPulse · Store %s · %s to %s · Data: FreshRetailNet-50K",
              m$store_id, m$date_min, m$date_max),
      if (synthetic) " · currently showing SYNTHETIC demo data")
  )
}

# Built pages are cached per store: building the UI (and compiling the theme's Sass)
# is the slowest part of a request, which matters on small instances.
# The final HTML is cached too, so a page request is a lookup instead of ~0.5 s of
# rendering (several seconds on a 0.1-CPU free instance, which made the host's
# HTTP port check time out).
.ui_cache <- new.env(parent = emptyenv())
cached_ui <- function(RP) {
  sid <- as.character(RP$manifest$store_id)
  if (is.null(.ui_cache[[sid]])) .ui_cache[[sid]] <- build_ui(RP, sid)
  .ui_cache[[sid]]
}
.html_cache <- new.env(parent = emptyenv())
cached_page <- function(RP) {
  sid <- as.character(RP$manifest$store_id)
  if (is.null(.html_cache[[sid]])) {
    html <- tryCatch(shiny:::renderPage(cached_ui(RP)), error = function(e) NULL)
    if (is.null(html)) return(cached_ui(RP))          # fall back to normal rendering
    .html_cache[[sid]] <- shiny::httpResponse(200L, "text/html; charset=UTF-8", html)
  }
  .html_cache[[sid]]
}

ui <- function(req) {
  if (!length(STORE_DIRS)) return(fatal_ui(list(out_dir = OUT_DIR)))
  sid <- store_from_query(req$QUERY_STRING)
  RP <- rp_get_store(STORE_DIRS, sid)
  if (!isTRUE(RP$ok)) return(fatal_ui(RP))
  cached_page(RP)
}

# Warm up BEFORE the server starts listening: load the default store, build its page
# and compile the theme, so the first request (and the host's health check) is fast.
if (length(STORE_DIRS)) {
  t0 <- Sys.time()
  try({
    RP0 <- rp_get_store(STORE_DIRS, names(STORE_DIRS)[1])
    # build the page and compile the theme now; the final HTML is cached on the first
    # request, because Shiny registers the page's script paths only once it is running
    if (isTRUE(RP0$ok)) invisible(htmltools::renderTags(cached_ui(RP0)))
  }, silent = FALSE)
  message(sprintf("RetailPulse warm-up done in %.1f s", as.numeric(difftime(Sys.time(), t0, units = "secs"))))
}

# App-wide cache for shiny::bindCache outputs, kept small for 512 MB instances
shiny::shinyOptions(cache = cachem::cache_mem(max_size = 40 * 1024^2))

# Shared, per-process cache of analysis results. Anomalies and recommendations depend
# only on (store, threshold, rule params, growth), not on the visitor, so every session
# reuses them instead of recomputing (seconds on a 0.1-CPU instance).
.calc_cache <- new.env(parent = emptyenv())
memo <- function(key, expr) {
  if (is.null(.calc_cache[[key]])) {
    if (length(ls(.calc_cache)) > 80) rm(list = ls(.calc_cache), envir = .calc_cache)
    .calc_cache[[key]] <- force(expr)
  }
  .calc_cache[[key]]
}
calc_anoms <- function(RP, zthr) {
  sid <- as.character(RP$manifest$store_id)
  memo(paste("an", sid, zthr), rp_classify_anomalies(RP$daily, zthr, stats::quantile(RP$daily$precpt, 0.9, na.rm = TRUE)))
}
calc_recs <- function(RP, params = list(), zthr, growth = 1) {
  sid <- as.character(RP$manifest$store_id)
  key <- paste("rec", sid, zthr, growth, if (length(params)) paste(deparse(params[order(names(params))]), collapse = "") else "default")
  memo(key, {
    an <- calc_anoms(RP, zthr)
    ind <- rp_product_indicators(RP$daily, RP$forecast_next, RP$manifest$chosen_model, an, RP$risk_next,
                                 RP$forecast_cv_product, RP$products[, c("product_id", "full_instock_days", "zero_sale_share")],
                                 growth = growth)
    rp_recommend(ind, params, risk_threshold = RP$manifest$risk_threshold)
  })
}
# Precompute a store's default results and draw each chart type once (the first plotly
# build in a process is ~30x slower than later ones).
warm_store <- function(RP) {
  z <- RP$manifest$thresholds$anomaly_z
  invisible(calc_recs(RP, list(), z))
  d <- RP$daily; last <- max(d$dt); x <- d[d$dt > last - 28, ]
  pid <- RP$products$product_id[1]
  for (w in list(ch_store_trend(RP$store_daily), ch_trend(d[d$product_id == pid, ], NULL, NULL)))
    try(plotly::plotly_build(w), silent = TRUE)
  invisible(reactable::reactable(data.frame(a = 1)))
}

server <- function(input, output, session) {
  if (!length(STORE_DIRS)) return()
  if (nzchar(Sys.getenv("RP_TIMING"))) {
    t_start <- Sys.time(); n_flush <- 0L
    if (nzchar(Sys.getenv("RP_PROFILE"))) Rprof(Sys.getenv("RP_PROFILE"), interval = 0.01)
    session$onFlushed(function() {
      n_flush <<- n_flush + 1L
      message(sprintf("[timing] flush %d after %.2f s", n_flush, as.numeric(difftime(Sys.time(), t_start, units = "secs"))))
      if (n_flush == 3L && nzchar(Sys.getenv("RP_PROFILE"))) Rprof(NULL)
    }, once = FALSE)
  }
  sid <- store_from_query(shiny::isolate(session$clientData$url_search))
  RP <- rp_get_store(STORE_DIRS, sid)
  if (!isTRUE(RP$ok)) return()
  sid <- as.character(RP$manifest$store_id)

  # switching store reloads the page with ?store=<id> so every module starts clean
  shiny::observeEvent(input$store, {
    if (!identical(as.character(input$store), sid)) {
      shiny::updateQueryString(paste0("?store=", input$store), mode = "replace")
      session$reload()
    }
  }, ignoreInit = TRUE)

  first <- RP$recommendations$product_id[1] %||% RP$products$product_id[1]
  # the anomaly threshold is fixed at the pipeline's value (3); its effect is shown, not adjustable
  state <- shiny::reactiveValues(product = first, date = NULL, zthr = RP$manifest$thresholds$anomaly_z, sim_sku = NULL)

  # The user's store catalogue lives in their browser (www/inventory.js). It is loaded once
  # per session and written back after every change. It is never mixed into RP.
  catalogue <- shiny::reactiveVal(NULL)
  storage_ok <- shiny::reactiveVal(NA)
  shiny::observeEvent(input$rp_catalogue, {
    p <- input$rp_catalogue
    storage_ok(isTRUE(p$available))
    if (!is.null(catalogue())) return()                     # already loaded (e.g. after a reconnect)
    x <- if (nzchar(p$data %||% "")) inv_from_json(p$data) else inv_empty()
    if (is.null(x)) { x <- inv_empty(); shiny::showNotification("Saved catalogue data in this browser could not be read, so the catalogue starts empty.", type = "warning") }
    catalogue(x)
  })
  save_catalogue <- function(x) {
    x <- x[order(x$name), , drop = FALSE]; rownames(x) <- NULL
    catalogue(x)
    session$sendCustomMessage("rp-catalogue-save", list(json = as.character(inv_to_json(x))))
  }
  shiny::observeEvent(input$rp_catalogue_saved, if (!isTRUE(input$rp_catalogue_saved$ok))
    shiny::showNotification("Could not save to this browser's storage; export a CSV to keep your changes.", type = "error"))

  anoms_r <- shiny::reactive(calc_anoms(RP, state$zthr))
  recs_r <- shiny::reactive(calc_recs(RP, list(), state$zthr))

  goto_product <- function(pid, date = NULL) {
    state$product <- as.integer(pid)
    state$date <- if (!is.null(date)) as.Date(date) else NULL
    bslib::nav_select("nav", "product", session = session)
  }
  goto_results <- function(tab) {
    bslib::nav_select("nav", "results", session = session)
    bslib::nav_select("rs-tab", tab, session = session)
  }
  goto_simulator <- function(sku) {
    state$sim_sku <- NULL; state$sim_sku <- sku
    bslib::nav_select("nav", "inventory", session = session)
  }

  # Only the Dashboard starts immediately; the other two pages' server logic starts the
  # first time each page is opened (less work per visit on small instances).
  mod_dashboard_server("db", RP, state, recs_r, anoms_r, goto_product, goto_results)
  starters <- list(
    product = function() mod_product_server("pr", RP, state, recs_r, anoms_r, catalogue, goto_simulator),
    inventory = function() mod_inventory_server("inv", RP, state, catalogue, save_catalogue, storage_ok, recs_r, goto_product),
    results = function() mod_results_server("rs", RP, state, recs_r, anoms_r))
  started <- character()
  shiny::observeEvent(input$nav, {
    pg <- input$nav
    if (pg %in% names(starters) && !pg %in% started) { started <<- c(started, pg); starters[[pg]]() }
  })
}

if (length(STORE_DIRS)) {
  t0 <- Sys.time()
  try(warm_store(rp_get_store(STORE_DIRS, names(STORE_DIRS)[1])), silent = FALSE)
  message(sprintf("RetailPulse results precomputed in %.1f s", as.numeric(difftime(Sys.time(), t0, units = "secs"))))
}

# Pre-render the default store's page once the app has started (Shiny's resource paths
# exist by then), so the first visitor and the host's port check get an instant reply.
prerender <- function() {
  if (!length(STORE_DIRS)) return(invisible())
  t0 <- Sys.time()
  try(invisible(cached_page(rp_get_store(STORE_DIRS, names(STORE_DIRS)[1]))), silent = TRUE)
  message(sprintf("RetailPulse first page pre-rendered in %.1f s", as.numeric(difftime(Sys.time(), t0, units = "secs"))))
}

shiny::shinyApp(ui, server, onStart = prerender)
