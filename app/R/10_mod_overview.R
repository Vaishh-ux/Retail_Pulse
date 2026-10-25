# Page 1 - Overview ----------------------------------------------------------------------
# Period and category filters drive the KPIs, trend, top products, category chart,
# heatmap and quick insights. Recommendations and stock alerts are always "as of the
# latest day in the data" (the rules look at the last 7 days), and say so.

mod_overview_ui <- function(id, RP) {
  ns <- shiny::NS(id)
  rng <- range(RP$daily$dt)
  cats <- sort(unique(RP$products$first_category_id))
  cat_choices <- c("All categories" = "", stats::setNames(cats, paste("Category", cats)))
  m <- RP$manifest
  htmltools::tagList(
    htmltools::div(class = "rp-hero",
      htmltools::div(
        htmltools::div(class = "rp-eyebrow", sprintf("Store %s · %d products · %s", m$store_id, m$products,
                                                     if (identical(m$mode, "synthetic")) "synthetic demo data" else "FreshRetailNet-50K")),
        htmltools::h1("Store overview"),
        htmltools::p(sprintf("Data runs from %s to %s. What needs attention first, and why.",
                             format(rng[1], "%d %b %Y"), format(rng[2], "%d %b %Y")))),
      htmltools::div(class = "rp-filters",
        shiny::selectInput(ns("period"), "Period", width = "150px", selected = "28",
          choices = c("Last 7 days" = "7", "Last 14 days" = "14", "Last 28 days" = "28", "Last 56 days" = "56", "Whole period" = "all", "Custom" = "custom")),
        shiny::dateRangeInput(ns("dates"), "Dates", start = rng[2] - 27, end = rng[2], min = rng[1], max = rng[2], width = "230px", format = "d M yyyy"),
        shiny::selectInput(ns("cat"), "Category", choices = cat_choices, width = "170px"))),
    shiny::uiOutput(ns("kpis")),
    bslib::layout_columns(
      col_widths = bslib::breakpoints(sm = 12, lg = c(8, 4)),
      bslib::card(full_screen = TRUE,
        bslib::card_header(rp_card_title("Sales and estimated demand", "Daily totals · red bars = out-of-stock hours · grey band = evaluation week", "chart-line")),
        plotly::plotlyOutput(ns("store"), height = "330px"),
        shiny::uiOutput(ns("store_note"))),
      bslib::card(
        bslib::card_header(rp_card_title("Priority stock alerts", "as of the latest day · click to investigate", "bell")),
        shiny::uiOutput(ns("alerts")),
        htmltools::div(class = "rp-dl-row", shiny::actionButton(ns("to_monitor"), "Open alert explorer", icon = shiny::icon("arrow-right"), class = "btn-outline-secondary btn-sm")))
    ),
    bslib::layout_columns(
      col_widths = bslib::breakpoints(sm = 12, lg = c(8, 4)),
      bslib::card(full_screen = TRUE,
        bslib::card_header(rp_card_title("Recommended actions", "Rule-based · pick an action type to filter · click a row to open the product", "list-check")),
        shiny::uiOutput(ns("action_tiles")),
        reactable::reactableOutput(ns("queue")),
        rp_note("Ranked by urgency × (estimated unmet demand + stockout risk + recent unusual activity). No order quantities are given: the dataset has no inventory, lead-time or cost fields. ",
                "Rules are listed under Data & Methods; weights can be changed under Forecast & Scenarios.")),
      bslib::card(
        bslib::card_header(rp_card_title("Quick insights", "for the selected period", "lightbulb")),
        shiny::uiOutput(ns("insights")))
    ),
    bslib::layout_columns(
      col_widths = bslib::breakpoints(sm = 12, lg = c(6, 6)),
      bslib::card(full_screen = TRUE,
        bslib::card_header(rp_card_title("Top products by estimated demand", "Recorded sales + estimated unmet demand · click a bar", "ranking-star")),
        plotly::plotlyOutput(ns("top"), height = "360px")),
      bslib::card(full_screen = TRUE,
        bslib::card_header(rp_card_title("Category performance", "Click a category to filter the page", "layer-group")),
        plotly::plotlyOutput(ns("cats"), height = "360px"))
    ),
    bslib::card(full_screen = TRUE,
      bslib::card_header(rp_card_title("Demand heatmap", "Product × day for the selected period · click a cell to open that product and date", "table-cells")),
      htmltools::div(class = "rp-heat-ctrl",
        shiny::selectInput(ns("heat_mode"), NULL, width = "290px",
          choices = c("Deviation from normal (robust z)" = "z", "Estimated demand vs usual level" = "demand", "Out-of-stock hours" = "stockout")),
        shiny::selectInput(ns("heat_rows"), NULL, width = "250px",
          choices = c("40 most unusual products" = "top40", "20 most unusual products" = "top20", "All products" = "all"))),
      shiny::uiOutput(ns("heat_wrap")),
      shiny::uiOutput(ns("heat_note")))
  )
}

mod_overview_server <- function(id, RP, state, anoms_r, recs_r, goto_product, goto_page = function(p) NULL) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns
    rng <- range(RP$daily$dt); last_dt <- rng[2]
    action_filter <- shiny::reactiveVal("")

    # ---- filters ----
    shiny::observeEvent(input$period, {
      if (input$period == "custom") return()
      start <- if (input$period == "all") rng[1] else max(rng[1], last_dt - as.integer(input$period) + 1)
      shiny::updateDateRangeInput(session, "dates", start = start, end = last_dt)
    }, ignoreInit = TRUE)
    shiny::observeEvent(input$dates, {
      r <- input$dates; shiny::req(length(r) == 2, !any(is.na(r)))
      preset <- c("7" = 7, "14" = 14, "28" = 28, "56" = 56)
      n <- as.integer(r[2] - r[1]) + 1
      sel <- if (r[2] == last_dt && r[1] == rng[1]) "all" else if (r[2] == last_dt && n %in% preset) names(preset)[preset == n] else "custom"
      if (!identical(sel, input$period)) shiny::updateSelectInput(session, "period", selected = sel)
    }, ignoreInit = TRUE)

    period <- shiny::reactive({
      r <- input$dates
      if (length(r) != 2 || any(is.na(r))) r <- c(last_dt - 27, last_dt)
      r <- sort(as.Date(r)); r[1] <- max(r[1], rng[1]); r[2] <- min(r[2], rng[2])
      r
    })
    cat_ids <- shiny::reactive({
      if (nzchar(input$cat %||% "")) RP$products$product_id[RP$products$first_category_id == as.integer(input$cat)] else RP$products$product_id
    })
    d_cat <- shiny::reactive(RP$daily[RP$daily$product_id %in% cat_ids(), ])
    d_per <- shiny::reactive({ p <- period(); x <- d_cat(); x[x$dt >= p[1] & x$dt <= p[2], ] })
    d_prev <- shiny::reactive({
      p <- period(); n <- as.integer(p[2] - p[1]) + 1
      x <- d_cat(); x[x$dt >= p[1] - n & x$dt < p[1], ]
    })
    recs_cat <- shiny::reactive({ r <- recs_r(); r[r$product_id %in% cat_ids(), ] })
    period_label <- shiny::reactive({ p <- period(); sprintf("%s – %s", format(p[1], "%d %b"), format(p[2], "%d %b %Y")) })

    # ---- KPIs ----
    output$kpis <- shiny::renderUI({
      x <- d_per(); pv <- d_prev(); m <- RP$manifest
      shiny::validate(shiny::need(nrow(x) > 0, "No data for this period and category."))
      chg <- function(a, b) if (is.na(b) || b <= 0) NA else a / b - 1
      rec <- sum(x$sale_amount); rec_p <- if (nrow(pv)) sum(pv$sale_amount) else NA
      dem <- sum(x$latent); dem_p <- if (nrow(pv)) sum(pv$latent) else NA
      unmet <- sum(x$lost) / max(dem, 1e-9); unmet_p <- if (nrow(pv)) sum(pv$lost) / max(sum(pv$latent), 1e-9) else NA
      so <- sum(x$stock_h) / (16 * nrow(x)); so_p <- if (nrow(pv)) sum(pv$stock_h) / (16 * nrow(pv)) else NA
      recs <- recs_cat()
      attn <- length(unique(recs$product_id[recs$urgency %in% c("High", "Medium")]))
      high <- length(unique(recs$product_id[recs$urgency == "High"]))
      ev <- RP$forecast_eval_overall
      w_chosen <- ev$WAPE[ev$.model == m$chosen_model]; w_base <- ev$WAPE[ev$.model == "snaive"]
      n_prod <- length(unique(x$product_id))
      htmltools::div(class = "rp-kpis",
        rp_kpi("Recorded sales", fmt_num(rec, 0), sprintf("%s · %d products · normalised units", period_label(), n_prod),
               "cart-shopping", "neutral", chg(rec, rec_p), if (is.na(chg(rec, rec_p))) NA else chg(rec, rec_p) >= 0),
        rp_kpi("Estimated demand", fmt_num(dem, 0), "Recorded sales plus estimated sales lost to stockouts (a model estimate)",
               "chart-column", "neutral", chg(dem, dem_p), if (is.na(chg(dem, dem_p))) NA else chg(dem, dem_p) >= 0),
        rp_kpi("Estimated unmet demand", fmt_pct(unmet, 1), sprintf("%s units of estimated demand went unmet", fmt_num(sum(x$lost), 0)),
               "box-open", tone_for(unmet, 0.05, 0.15), chg(unmet, unmet_p), if (is.na(chg(unmet, unmet_p))) NA else chg(unmet, unmet_p) <= 0),
        rp_kpi("Stockout-hour rate", fmt_pct(so, 1), "Share of 06:00–22:00 trading hours out of stock",
               "store-slash", tone_for(so, 0.08, 0.15), chg(so, so_p), if (is.na(chg(so, so_p))) NA else chg(so, so_p) <= 0),
        rp_kpi("Needs attention", attn, sprintf("%d high urgency · as of %s · %d anomalies at |z| ≥ %.1f", high, format(last_dt, "%d %b"),
                                               sum(anoms_r()$product_id %in% cat_ids()), state$zthr),
               "triangle-exclamation", if (high > 0) "warning" else "good"),
        rp_kpi(sprintf("Forecast error (%s)", toupper(m$chosen_model)), fmt_pct(w_chosen, 1),
               sprintf("WAPE on the held-out week; seasonal naive %s. Lower is better.", fmt_pct(w_base, 1)), "bullseye", "neutral"))
    })

    # ---- trend ----
    agg_daily <- shiny::reactive({
      x <- d_per(); shiny::req(nrow(x))
      a <- stats::aggregate(cbind(observed = sale_amount, latent = latent, stockout_hours = stock_h) ~ dt + split, x, sum)
      a[order(a$dt), ]
    })
    output$store <- plotly::renderPlotly(ch_store_trend(agg_daily()))
    output$store_note <- shiny::renderUI({
      a <- agg_daily()
      gap <- sum(a$latent - a$observed)
      worst <- a[which.max(a$latent - a$observed), ]
      rp_note(sprintf("Between %s, estimated demand exceeds recorded sales by %s units (%s of estimated demand). The largest gap was on %s (%s units, %d stockout hours). ",
                      period_label(), fmt_num(gap, 1), fmt_pct(gap / max(sum(a$latent), 1e-9), 1), format(worst$dt, "%a %d %b"),
                      fmt_num(worst$latent - worst$observed, 1), as.integer(worst$stockout_hours)),
              "Estimated demand is a model output, not a measurement.")
    })

    # ---- stock alerts ----
    output$alerts <- shiny::renderUI({
      r <- recs_cat(); r <- r[r$action == "Consider replenishing earlier", ]
      if (!nrow(r)) return(htmltools::div(class = "rp-empty", shiny::icon("circle-check"), " No products currently meet the stockout rules."))
      n_total <- length(unique(r$product_id))
      r <- utils::head(r[order(-r$priority), ], 6)
      thr <- RP$manifest$risk_threshold
      items <- lapply(seq_len(nrow(r)), function(i) {
        sev <- if (r$urgency[i] == "High") "critical" else "warning"
        risk <- r$risk[i]
        col <- if (is.na(risk)) RP_COL$muted else if (risk >= thr) RP_COL$red else RP_COL$amber
        htmltools::tags$button(type = "button", class = "rp-alert",
          onclick = sprintf("Shiny.setInputValue('%s', %d, {priority: 'event'})", ns("alert_click"), r$product_id[i]),
          htmltools::span(class = paste("rp-alert-sev", sev)),
          htmltools::span(class = "rp-alert-name", sprintf("%s · %s", plabel(r$product_id[i]), RP$products$category[match(r$product_id[i], RP$products$product_id)])),
          htmltools::span(class = "rp-alert-meta",
            rp_badge(if (sev == "critical") "Critical" else "Warning", sev),
            htmltools::span(class = "rp-riskbar", htmltools::span(style = sprintf("width:%.0f%%;background:%s", 100 * min(1, risk %||% 0), col))),
            htmltools::span(class = "rp-riskval", sprintf("next-day risk %s", fmt_pct(risk)))),
          htmltools::span(class = "rp-alert-why", sprintf("Out of stock 4+ hours on %d of the last 7 days · %s of demand unmet",
                                                          as.integer(r$stockout_days7[i]), fmt_pct(r$lost_share7[i], 0))))
      })
      htmltools::tagList(htmltools::div(class = "rp-alert-list", items),
        rp_note(sprintf("Top %d of %d products that meet the stockout rule (R1). Risk is a historical-pattern score for tomorrow, not stock on hand: the data has no inventory field.", nrow(r), n_total)))
    })
    shiny::observeEvent(input$alert_click, goto_product(input$alert_click))
    shiny::observeEvent(input$to_monitor, goto_page("monitor"))

    # ---- recommended actions ----
    output$action_tiles <- shiny::renderUI({
      r <- recs_cat()
      icons <- c("Consider replenishing earlier" = "truck-ramp-box", "Review possible demand surge" = "arrow-trend-up",
                 "Investigate unexplained sales drop" = "magnifying-glass", "Plan for lower demand" = "arrow-trend-down",
                 "Use caution: forecast unreliable" = "circle-question", "Maintain current approach" = "circle-check")
      counts <- vapply(names(icons), function(a) length(unique(r$product_id[r$action == a])), 0L)
      sel <- action_filter()
      tile <- function(key, n, label, icon) htmltools::tags$button(type = "button", class = paste("rp-action", if (identical(sel, key)) "active"),
        onclick = sprintf("Shiny.setInputValue('%s', '%s', {priority: 'event'})", ns("action_pick"), key),
        htmltools::span(class = "rp-action-top", htmltools::span(class = "rp-action-n", n), shiny::icon(icon)),
        htmltools::span(class = "rp-action-l", label))
      htmltools::div(class = "rp-actions",
        tile("", length(unique(r$product_id[r$action != "Maintain current approach"])), "All products needing action", "layer-group"),
        lapply(names(icons)[counts > 0], function(a) tile(a, counts[[a]], a, icons[[a]])))
    })
    shiny::observeEvent(input$action_pick, action_filter(input$action_pick))

    output$queue <- reactable::renderReactable({
      recs <- recs_cat(); a <- action_filter()
      top <- if (nzchar(a)) recs[recs$action == a, ] else recs[!duplicated(recs$product_id) & recs$action != "Maintain current approach", ]
      top <- top[order(-top$priority), ]
      if (!nrow(top)) return(reactable::reactable(data.frame(Message = "No products currently need this action.")))
      tb <- data.frame(product_id = top$product_id, Product = plabel(top$product_id), Action = top$action,
                       Urgency = top$urgency, Why = top$reason, Reliability = top$reliability, Priority = top$priority)
      reactable::reactable(tb, compact = TRUE, highlight = TRUE, pagination = TRUE, defaultPageSize = 6, searchable = TRUE,
        rowStyle = list(cursor = "pointer"), language = reactable::reactableLang(searchPlaceholder = "Search products, actions, reasons…"),
        onClick = reactable::JS(sprintf("function(rowInfo){ Shiny.setInputValue('%s', rowInfo.values.product_id, {priority: 'event'}) }", ns("queue_click"))),
        columns = list(
          product_id = reactable::colDef(show = FALSE),
          Product = reactable::colDef(width = 86, style = list(fontWeight = 700, color = RP_COL$forest)),
          Action = reactable::colDef(minWidth = 140),
          Urgency = reactable::colDef(width = 92, cell = function(v) rp_badge(v, urgency_kind(v))),
          Why = reactable::colDef(minWidth = 220, style = list(fontSize = "0.8rem", color = RP_COL$ink2), sortable = FALSE),
          Reliability = reactable::colDef(name = "Forecast", width = 90, cell = function(v) rp_badge(v, c(High = "good", Medium = "neutral", Low = "warning")[[v]])),
          Priority = reactable::colDef(width = 80, format = reactable::colFormat(digits = 2))
        ))
    })
    shiny::observeEvent(input$queue_click, goto_product(input$queue_click))

    # ---- quick insights ----
    output$insights <- shiny::renderUI({
      x <- d_per(); pv <- d_prev(); shiny::req(nrow(x))
      ins <- list()
      add <- function(icon, kind, ...) ins[[length(ins) + 1]] <<- htmltools::div(class = "rp-insight",
        htmltools::span(class = paste("rp-insight-icon", kind), shiny::icon(icon)), htmltools::p(...))
      # 1 unmet demand
      byp <- stats::aggregate(cbind(lost, latent) ~ product_id, x, sum)
      share <- sum(x$lost) / max(sum(x$latent), 1e-9)
      add("box-open", if (share >= 0.15) "bad" else if (share >= 0.05) "warn" else "",
          htmltools::strong(sprintf("%s of estimated demand went unmet. ", fmt_pct(share, 0))),
          sprintf("%d of %d products lost more than 20%% of their estimated demand to stockouts.", sum(byp$lost / pmax(byp$latent, 1e-9) > 0.2), nrow(byp)))
      # 2 demand change and the category that drove it
      if (nrow(pv)) {
        ch <- sum(x$latent) / max(sum(pv$latent), 1e-9) - 1
        cc <- merge(stats::aggregate(latent ~ first_category_id, x, sum), stats::aggregate(latent ~ first_category_id, pv, sum), by = "first_category_id", suffixes = c("", "_p"))
        cc$diff <- cc$latent - cc$latent_p
        lead <- if (nrow(cc)) cc[which.max(abs(cc$diff)), ] else NULL
        add(if (ch >= 0) "arrow-trend-up" else "arrow-trend-down", "gold",
            htmltools::strong(sprintf("Estimated demand is %s %s ", if (ch >= 0) "up" else "down", fmt_pct(abs(ch), 0))),
            sprintf("versus the previous %d days%s.", as.integer(diff(period())) + 1,
                    if (!is.null(lead)) sprintf("; the biggest change is in Category %s (%s%s units)", lead$first_category_id, if (lead$diff >= 0) "+" else "−", fmt_num(abs(lead$diff), 1)) else ""))
      }
      # 3 when the store sells / sells out
      w <- RP$store_weekday_hour
      if (NROW(w)) {
        by_h <- stats::aggregate(mean_sales ~ hour, w, mean); by_d <- stats::aggregate(mean_sales ~ weekday, w, mean)
        so <- RP$sellout_summary$median_sellout_hour[RP$sellout_summary$product_id %in% unique(x$product_id)]
        add("clock", "", htmltools::strong(sprintf("Busiest hour: %02d:00; busiest day: %s. ", by_h$hour[which.max(by_h$mean_sales)],
                                                   c("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")[by_d$weekday[which.max(by_d$mean_sales)]])),
            if (sum(!is.na(so))) sprintf("%d products are usually out of stock by mid-evening; the median sell-out hour among them is %02.0f:00.", sum(!is.na(so)), stats::median(so, na.rm = TRUE))
            else "No product sells out on most days.")
      }
      # 4 unexplained anomalies
      a <- anoms_r(); p <- period(); a <- a[a$dt >= p[1] & a$dt <= p[2] & a$product_id %in% unique(x$product_id), ]
      ue <- a[a$cause == "Unexplained", ]
      add("magnifying-glass", if (nrow(ue)) "warn" else "",
          htmltools::strong(sprintf("%d unusual product-days, %d unexplained. ", nrow(a), nrow(ue))),
          if (nrow(ue)) sprintf("Most recent: %s on %s (%s). These have no stockout, promotion, holiday or heavy-rain flag.",
                                plabel(ue$product_id[which.max(ue$dt)]), format(max(ue$dt), "%a %d %b"), ue$direction[which.max(ue$dt)])
          else "Every flagged day coincides with a stockout, promotion, holiday or heavy rain.")
      # 5 promotion association (observational)
      pr <- x[!is.na(x$promo), ]
      pp <- stats::aggregate(latent ~ product_id + promo, pr[pr$stock_h < 4, ], mean)
      wide <- merge(pp[pp$promo == 1, ], pp[pp$promo == 0, ], by = "product_id", suffixes = c("_p", "_n"))
      if (nrow(wide) >= 5) {
        ratio <- stats::median(wide$latent_p / pmax(wide$latent_n, 1e-9))
        add("tag", "", htmltools::strong(sprintf("Promotion days: median %s%s estimated demand. ", if (ratio >= 1) "+" else "−", fmt_pct(abs(ratio - 1), 0))),
            sprintf("Compared within the same %d products on mostly in-stock days. This is an association, not a measured promotion effect.", nrow(wide)))
      }
      htmltools::div(class = "rp-insights", ins)
    })

    # ---- top products & categories ----
    output$top <- plotly::renderPlotly({
      x <- d_per(); shiny::req(nrow(x))
      tp <- stats::aggregate(cbind(observed = sale_amount, latent = latent) ~ product_id, x, sum)
      tp$unmet_share <- (tp$latent - tp$observed) / pmax(tp$latent, 1e-9)
      ch_top_products(utils::head(tp[order(-tp$latent), ], 12), source = ns("top"))
    })
    shiny::observeEvent(plotly::event_data("plotly_click", source = ns("top")), {
      ev <- plotly::event_data("plotly_click", source = ns("top"))
      pid <- suppressWarnings(as.integer(sub("^P", "", ev$y %||% "")))
      if (length(pid) && !is.na(pid)) goto_product(pid)
    })
    output$cats <- plotly::renderPlotly({
      p <- period(); x <- RP$daily[RP$daily$dt >= p[1] & RP$daily$dt <= p[2], ]
      shiny::req(nrow(x))
      cp <- stats::aggregate(cbind(observed = sale_amount, latent = latent, stock_h = stock_h) ~ first_category_id, x, sum)
      cp$products <- as.integer(table(RP$products$first_category_id)[as.character(cp$first_category_id)])
      cp$n <- as.integer(table(x$first_category_id)[as.character(cp$first_category_id)])
      cp$so_rate <- cp$stock_h / (16 * cp$n)
      cp$unmet_share <- (cp$latent - cp$observed) / pmax(cp$latent, 1e-9)
      cp$category <- paste("Category", cp$first_category_id)
      cp <- utils::head(cp[order(-cp$latent), ], 12)
      ch_categories(cp, source = ns("cats"))
    })
    shiny::observeEvent(plotly::event_data("plotly_click", source = ns("cats")), {
      ev <- plotly::event_data("plotly_click", source = ns("cats"))
      cid <- suppressWarnings(as.integer(sub("^Category ", "", ev$y %||% "")))
      if (length(cid) && !is.na(cid)) shiny::updateSelectInput(session, "cat", selected = if (identical(input$cat, as.character(cid))) "" else cid)
    })

    # ---- heatmap ----
    heat_data <- shiny::reactive({
      d <- d_cat(); p <- period()
      w <- d[d$dt >= p[1] & d$dt <= p[2], ]
      score <- tapply(pmax(abs(w$z), 0, na.rm = TRUE) * (abs(w$z) >= state$zthr), w$product_id, sum, na.rm = TRUE)
      score[is.na(score)] <- 0
      n <- switch(input$heat_rows %||% "top40", top40 = 40, top20 = 20, Inf)
      keep <- as.integer(names(sort(score, decreasing = TRUE)))[seq_len(min(length(score), n))]
      d[d$product_id %in% keep, ]
    })
    output$heat_wrap <- shiny::renderUI({
      n <- length(unique(heat_data()$product_id))
      plotly::plotlyOutput(ns("heat"), height = paste0(max(320, 120 + 13 * n), "px"))
    })
    output$heat <- plotly::renderPlotly({
      x <- heat_data(); if (!nrow(x)) return(rp_empty_plot("No products in this category"))
      p <- period()
      ch_heatmap(x, RP$label_of, source = ns("heat"), mode = input$heat_mode %||% "z", start = p[1], end = p[2])
    })
    shiny::observeEvent(plotly::event_data("plotly_click", source = ns("heat")), {
      ev <- plotly::event_data("plotly_click", source = ns("heat"))
      if (is.null(ev$y) || is.null(ev$x)) return()
      pid <- as.integer(sub("^P", "", ev$y))
      if (!is.na(pid)) goto_product(pid, as.Date(ev$x))
    })
    output$heat_note <- shiny::renderUI({
      p <- period(); a <- anoms_r(); a <- a[a$dt >= p[1] & a$dt <= p[2] & a$product_id %in% cat_ids(), ]
      shown <- length(unique(heat_data()$product_id))
      legend <- switch(input$heat_mode %||% "z",
        z = "Green = below the product's normal level, gold = above; a white × marks a day with 4+ stockout hours, where the low value is censored.",
        demand = "Darker = more estimated demand relative to the product's own average in this period; red × = 4+ stockout hours.",
        stockout = "Darker red = more trading hours out of stock (0–16).")
      rp_note(sprintf("Showing %d of %d products, ordered by product ID; the selection ranks products by the size of their flags in the period. ", shown, length(cat_ids())),
              sprintf("In this period, %d product-days were flagged at |z| ≥ %.1f: %d explained by a stockout, promotion, holiday or rain, and %d unexplained. ",
                      nrow(a), state$zthr, sum(a$cause != "Unexplained"), sum(a$cause == "Unexplained")), legend)
    })
  })
}
