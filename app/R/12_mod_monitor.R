# Page 3 - Monitoring and alerts ------------------------------------------------------------------
# The replay steps through the evaluation week's HISTORICAL hourly records.
# At simulated time t, only alerts with timestamp <= t are shown.

mod_monitor_ui <- function(id, choices) {
  ns <- shiny::NS(id)
  bslib::navset_card_tab(id = ns("tabs"),
    bslib::nav_panel("Simulated hourly replay",
      htmltools::div(class = "rp-replay-banner", shiny::icon("clock-rotate-left"), htmltools::div(htmltools::strong("Historical replay — not a live feed. "),
        "Hour-by-hour records from the evaluation week are revealed in timestamp order. Expected values come from forecasts made before that week; ",
        "alerts use only data up to the simulated time. RetailPulse is not connected to a till or stock system.")),
      bslib::layout_columns(col_widths = bslib::breakpoints(sm = 12, lg = c(3, 9)),
        htmltools::div(class = "rp-controls",
          shiny::uiOutput(ns("clock")),
          htmltools::div(class = "rp-btns",
            shiny::actionButton(ns("play"), "Play", icon = shiny::icon("play"), class = "btn-primary btn-sm"),
            shiny::actionButton(ns("pause"), "Pause", icon = shiny::icon("pause"), class = "btn-outline-secondary btn-sm"),
            shiny::actionButton(ns("reset"), "Reset", icon = shiny::icon("rotate-left"), class = "btn-outline-secondary btn-sm")),
          shiny::selectInput(ns("speed"), "Speed", c("1 hour / 2 s" = 2000, "1 hour / s" = 1000, "2 hours / s" = 500, "4 hours / s" = 250), selected = 1000),
          shiny::sliderInput(ns("step"), "Timeline (hour of the replay week)", min = 1, max = 168, value = 1, step = 1, ticks = FALSE),
          shiny::uiOutput(ns("step_label")),
          shiny::selectInput(ns("jump_day"), "Jump to day (06:00)", choices = NULL),
          shiny::selectizeInput(ns("product"), "Product to watch", choices = choices, options = list(placeholder = "Search product…")),
          shiny::checkboxInput(ns("only_prod"), "Show alerts for this product only", FALSE),
          shiny::uiOutput(ns("now_stats"))),
        htmltools::tagList(
          bslib::card(full_screen = TRUE,
            bslib::card_header(shiny::uiOutput(ns("replay_title"), inline = TRUE)),
            plotly::plotlyOutput(ns("replay_plot"), height = "340px"),
            shiny::uiOutput(ns("replay_note"))),
          bslib::card(bslib::card_header(shiny::uiOutput(ns("so_far_title"), inline = TRUE)),
                      htmltools::div(class = "rp-legend", htmltools::span(class = "crit", "Critical: out of stock in a peak hour"),
                                     htmltools::span(class = "warn", "Warning: outside the expected range for 3+ hours"),
                                     htmltools::span(class = "info", "Info: out of stock outside peak hours")),
                      reactable::reactableOutput(ns("alerts_so_far")),
                      rp_note("Click an alert to open that product on that day."))))
    ),
    bslib::nav_panel("Alert explorer",
      bslib::layout_columns(col_widths = bslib::breakpoints(sm = 12, md = c(3, 3, 3, 3)),
        shiny::selectizeInput(ns("f_type"), "Alert type", choices = NULL, multiple = TRUE, options = list(placeholder = "All types")),
        shiny::selectizeInput(ns("f_sev"), "Severity / risk category", choices = c("Critical", "Warning", "Info", "Anomaly"), multiple = TRUE, options = list(placeholder = "All")),
        shiny::selectizeInput(ns("f_prod"), "Product", choices = choices, multiple = TRUE, options = list(placeholder = "All products")),
        shiny::dateRangeInput(ns("f_dates"), "Period")),
      bslib::layout_columns(col_widths = bslib::breakpoints(sm = 12, lg = c(8, 4)),
        bslib::card(reactable::reactableOutput(ns("explorer")), shiny::uiOutput(ns("explorer_note"))),
        bslib::card(bslib::card_header(htmltools::div(class = "rp-card-title", "Alert detail")), shiny::uiOutput(ns("detail"))))
    )
  )
}

mod_monitor_server <- function(id, RP, state, anoms_r, goto_product) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns
    rp <- RP$replay
    times <- sort(unique(rp$ts))
    n_t <- length(times)
    shiny::updateSliderInput(session, "step", max = max(1, n_t))
    start_i <- max(1L, which(as.integer(format(times, "%H")) == 6L)[1] %||% 1L)
    step <- shiny::reactiveVal(start_i); playing <- shiny::reactiveVal(FALSE)
    shiny::updateSliderInput(session, "step", value = start_i)

    shiny::observeEvent(input$play, playing(TRUE))
    shiny::observeEvent(input$pause, playing(FALSE))
    shiny::observeEvent(input$reset, { playing(FALSE); step(start_i); shiny::updateSliderInput(session, "step", value = start_i) })
    days <- unique(as.Date(format(times, "%Y-%m-%d")))
    shiny::updateSelectInput(session, "jump_day", choices = c("Choose a day…" = "", stats::setNames(as.character(days), format(days, "%a %d %b"))))
    shiny::observeEvent(input$jump_day, {
      shiny::req(nzchar(input$jump_day))
      i <- which(format(times, "%Y-%m-%d") == input$jump_day & as.integer(format(times, "%H")) == 6L)[1]
      if (!is.na(i)) { playing(FALSE); step(i); shiny::updateSliderInput(session, "step", value = i) }
    }, ignoreInit = TRUE)
    output$step_label <- shiny::renderUI({ t <- now(); shiny::req(!is.na(t))
      htmltools::p(class = "rp-sub", style = "margin-top:-.6rem", sprintf("Hour %d of %d · %s", min(step(), n_t), n_t, format(t, "%a %d %b, %H:00"))) })
    shiny::observeEvent(input$step, if (!playing()) step(as.integer(input$step)), ignoreInit = TRUE)
    shiny::observe({
      shiny::req(playing())
      shiny::invalidateLater(as.numeric(input$speed))
      shiny::isolate({
        if (step() >= n_t) { playing(FALSE); return() }
        step(step() + 1L)
        shiny::updateSliderInput(session, "step", value = step())
      })
    })
    now <- shiny::reactive(if (n_t) times[min(step(), n_t)] else NA)
    shiny::observeEvent(state$product, shiny::updateSelectizeInput(session, "product", selected = state$product), ignoreNULL = TRUE)

    output$clock <- shiny::renderUI({
      t <- now(); shiny::req(!is.na(t))
      htmltools::div(class = paste("rp-clock", if (playing()) "playing"), htmltools::span("Simulated time"), htmltools::strong(format(t, "%a %d %b %Y, %H:00")),
                     htmltools::span(class = "rp-live", "HISTORICAL REPLAY"),
                     htmltools::span(class = "rp-sub", if (playing()) sprintf("replaying at %s…", c("2000" = "1 h / 2 s", "1000" = "1 h / s", "500" = "2 h / s", "250" = "4 h / s")[[as.character(input$speed)]]) else "paused"))
    })
    so_far <- shiny::reactive({ t <- now(); a <- RP$alerts; if (!nrow(a) || is.na(t)) a[0, ] else a[a$ts <= t, ] })
    output$now_stats <- shiny::renderUI({
      t <- now(); shiny::req(!is.na(t))
      cur <- rp[rp$ts == t, ]; a <- so_far()
      htmltools::div(class = "rp-facts",
        htmltools::div(htmltools::span("Products out of stock now"), htmltools::strong(sum(cur$out == 1 & cur$hour %in% 6:21))),
        htmltools::div(htmltools::span("Critical alerts so far"), htmltools::strong(sum(a$severity == "Critical"))),
        htmltools::div(htmltools::span("Warnings so far"), htmltools::strong(sum(a$severity == "Warning"))))
    })
    output$replay_title <- shiny::renderUI({
      t <- now(); shiny::req(!is.na(t))
      htmltools::div(class = "rp-card-title", sprintf("Is %s on track today?", plabel(input$product)),
                     htmltools::span(class = "rp-sub", sprintf("%s · observed cumulative sales vs expected range", format(t, "%A %d %b"))))
    })
    output$replay_plot <- plotly::renderPlotly({
      t <- now(); shiny::req(!is.na(t), input$product)
      g <- rp[rp$product_id == as.integer(input$product) & rp$dt == as.Date(t), ]
      ch_replay(g, as.integer(format(t, "%H")))
    })
    output$replay_note <- shiny::renderUI({
      t <- now(); shiny::req(!is.na(t), input$product)
      g <- rp[rp$product_id == as.integer(input$product) & rp$dt == as.Date(t) & rp$hour <= as.integer(format(t, "%H")), ]
      shiny::req(nrow(g))
      last <- g[nrow(g), ]
      tol <- 1e-6
      status <- if (last$hour < 6) "before trading hours" else if (last$out == 1 && last$hour %in% 6:21) "out of stock" else if (last$cum_obs < last$cum_lo - tol) "below the expected range"
                else if (last$cum_obs > last$cum_hi + tol) "above the expected range" else "within the expected range"
      rp_note(sprintf("At %02d:00 cumulative sales are %s vs %s expected, so the product is %s. Red shading marks out-of-stock hours.",
                      last$hour, fmt_num(last$cum_obs, 2), fmt_num(last$cum_exp, 2), status))
    })
    so_far_view <- shiny::reactive({
      a <- so_far()
      if (isTRUE(input$only_prod) && nzchar(input$product %||% "")) a <- a[a$product_id == as.integer(input$product), ]
      a[order(a$ts, decreasing = TRUE), ]
    })
    output$so_far_title <- shiny::renderUI(htmltools::div(class = "rp-card-title", "Alerts raised so far",
      htmltools::span(class = "rp-sub", sprintf("%s · %d alerts · newest first", if (isTRUE(input$only_prod)) plabel(input$product) else "all products", nrow(so_far_view())))))
    output$alerts_so_far <- reactable::renderReactable({
      a <- so_far_view()
      if (!nrow(a)) return(reactable::reactable(data.frame(Message = "No alerts yet at this simulated time.")))
      a <- a[order(a$ts, decreasing = TRUE), ]
      tb <- data.frame(pid = a$product_id, day = format(a$dt), Time = format(a$ts, "%a %H:00"), Product = plabel(a$product_id), Severity = a$severity, Type = a$type, Detail = a$message)
      reactable::reactable(tb, compact = TRUE, defaultPageSize = 6, highlight = TRUE, rowStyle = list(cursor = "pointer"),
        onClick = reactable::JS(sprintf("function(rowInfo){ Shiny.setInputValue('%s', {pid: rowInfo.values.pid, day: rowInfo.values.day}, {priority: 'event'}) }", ns("sofar_click"))),
        columns = list(pid = reactable::colDef(show = FALSE), day = reactable::colDef(show = FALSE), Severity = reactable::colDef(width = 90, cell = function(v) rp_badge(v, tolower(v))),
                       Product = reactable::colDef(width = 86), Time = reactable::colDef(width = 80)))
    })

    shiny::observeEvent(input$sofar_click, goto_product(input$sofar_click$pid, input$sofar_click$day))

    # ---- explorer ----
    all_alerts <- shiny::reactive({
      ra <- RP$alerts
      r1 <- if (nrow(ra)) tibble::tibble(when = format(ra$ts, "%Y-%m-%d %H:00"), date = as.Date(ra$dt), product_id = ra$product_id,
                                         source = "Hourly replay", type = ra$type, severity = ra$severity,
                                         observed = ra$observed, expected = ra$expected, deviation = ra$observed - ra$expected,
                                         method = ifelse(ra$type == "Out of stock", "Stock status turned to unavailable during trading hours",
                                                         "Cumulative sales outside forecast-based 80% range for 3 consecutive hours"),
                                         explanation = ra$message) else NULL
      an <- anoms_r()
      r2 <- if (NROW(an)) tibble::tibble(when = format(an$dt), date = an$dt, product_id = an$product_id, source = "Daily anomaly",
                                         type = paste0(tools::toTitleCase(an$direction), ": ", an$cause), severity = "Anomaly",
                                         observed = an$observed, expected = an$expected, deviation = an$deviation,
                                         method = an$method, explanation = paste(an$explanation, an$note)) else NULL
      dplyr::bind_rows(r1, r2)
    })
    shiny::observe({
      a <- all_alerts(); shiny::req(nrow(a))
      shiny::updateSelectizeInput(session, "f_type", choices = sort(unique(a$type)), server = FALSE)
      shiny::updateDateRangeInput(session, "f_dates", start = min(a$date), end = max(a$date), min = min(a$date), max = max(a$date))
    })
    filtered <- shiny::reactive({
      a <- all_alerts(); if (!nrow(a)) return(a)
      if (length(input$f_type)) a <- a[a$type %in% input$f_type, ]
      if (length(input$f_sev)) a <- a[a$severity %in% input$f_sev, ]
      if (length(input$f_prod)) a <- a[a$product_id %in% as.integer(input$f_prod), ]
      r <- input$f_dates
      if (length(r) == 2 && !any(is.na(r))) a <- a[a$date >= r[1] & a$date <= r[2], ]
      a[order(a$date, decreasing = TRUE), ]
    })
    output$explorer <- reactable::renderReactable({
      a <- filtered()
      if (!nrow(a)) return(reactable::reactable(data.frame(Message = "No alerts match these filters. Clear a filter to see more.")))
      tb <- data.frame(row = seq_len(nrow(a)), When = a$when, Product = plabel(a$product_id), Source = a$source, Type = a$type,
                       Severity = a$severity, Observed = a$observed, Expected = a$expected, Deviation = a$deviation)
      reactable::reactable(tb, searchable = TRUE, compact = TRUE, highlight = TRUE, defaultPageSize = 12, defaultSorted = "When",
        defaultSortOrder = "desc", rowStyle = list(cursor = "pointer"),
        onClick = reactable::JS(sprintf("function(rowInfo){ Shiny.setInputValue('%s', rowInfo.values.row, {priority: 'event'}) }", ns("pick"))),
        columns = list(row = reactable::colDef(show = FALSE),
                       Severity = reactable::colDef(width = 92, cell = function(v) rp_badge(v, tolower(v))),
                       Observed = reactable::colDef(format = reactable::colFormat(digits = 2), width = 86),
                       Expected = reactable::colDef(format = reactable::colFormat(digits = 2), width = 86),
                       Deviation = reactable::colDef(format = reactable::colFormat(digits = 2), width = 90)))
    })
    output$explorer_note <- shiny::renderUI(rp_note(sprintf("%d alerts shown. Daily anomalies use the current threshold |z| ≥ %.1f (adjustable under Scenarios). Anomalies are statistical signals, not confirmed problems.",
                                                           nrow(filtered()), state$zthr)))
    picked <- shiny::reactiveVal(NULL)
    shiny::observeEvent(input$pick, picked(input$pick))
    output$detail <- shiny::renderUI({
      i <- picked(); a <- filtered()
      if (is.null(i) || i > nrow(a)) return(htmltools::p(class = "rp-sub", "Click an alert to see why it was raised."))
      r <- a[i, ]
      htmltools::div(class = "rp-detail",
        htmltools::h4(sprintf("%s · %s", plabel(r$product_id), r$when)),
        rp_badge(r$severity, tolower(r$severity)), htmltools::p(htmltools::strong(r$type)),
        htmltools::p(r$explanation),
        htmltools::tags$dl(htmltools::tags$dt("Observed"), htmltools::tags$dd(fmt_num(r$observed, 3)),
                           htmltools::tags$dt("Expected / reference"), htmltools::tags$dd(fmt_num(r$expected, 3)),
                           htmltools::tags$dt("Deviation"), htmltools::tags$dd(fmt_num(r$deviation, 3)),
                           htmltools::tags$dt("Detection method"), htmltools::tags$dd(r$method)),
        shiny::actionButton(ns("open"), "Open this product", class = "btn-primary btn-sm"))
    })
    shiny::observeEvent(input$open, { i <- picked(); a <- filtered(); shiny::req(i <= nrow(a)); goto_product(a$product_id[i], a$date[i]) })
  })
}
