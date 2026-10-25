# Page 2 - Product intelligence ---------------------------------------------------------------

mod_product_ui <- function(id, choices) {
  ns <- shiny::NS(id)
  bslib::layout_sidebar(
    sidebar = bslib::sidebar(width = 290, open = list(desktop = "open", mobile = "closed"),
      shiny::selectizeInput(ns("product"), "Product", choices = choices, options = list(placeholder = "Search product ID…")),
      shiny::selectizeInput(ns("compare"), "Compare with (optional)", choices = c("None" = "", choices)),
      shiny::sliderInput(ns("horizon"), "Forecast horizon (days)", min = 1, max = 14, value = 7, step = 1),
      shiny::uiOutput(ns("horizon_note")),
      shiny::checkboxInput(ns("show_fc"), "Show forecast", TRUE),
      shiny::dateRangeInput(ns("range"), "Date range", start = NULL, end = NULL),
      htmltools::hr(),
      shiny::uiOutput(ns("facts"))
    ),
    shiny::uiOutput(ns("header")),
    bslib::card(full_screen = TRUE,
      bslib::card_header(htmltools::div(class = "rp-card-title", "Is demand really changing, or are stockouts hiding it?",
                                        htmltools::span(class = "rp-sub", "Recorded sales vs estimated demand · gold shading = promotion · red bars = out-of-stock hours · gold dotted = comparison product"))),
      plotly::plotlyOutput(ns("trend"), height = "440px"),
      shiny::uiOutput(ns("trend_note"))),
    shiny::uiOutput(ns("recs")),
    bslib::layout_columns(col_widths = bslib::breakpoints(sm = 12, lg = c(6, 6)),
      bslib::card(full_screen = TRUE,
        bslib::card_header(htmltools::div(class = "rp-card-title", "When do customers buy it?",
                                          htmltools::span(class = "rp-sub", "Mean recorded sales per in-stock hour, by weekday and hour"))),
        plotly::plotlyOutput(ns("wdh"), height = "300px"), shiny::uiOutput(ns("wdh_note"))),
      bslib::card(full_screen = TRUE,
        bslib::card_header(htmltools::div(class = "rp-card-title", "When does it usually run out?",
                                          htmltools::span(class = "rp-sub", "Kaplan–Meier: share of days still in stock at each hour"))),
        plotly::plotlyOutput(ns("sellout"), height = "300px"), shiny::uiOutput(ns("sellout_note")))
    ),
    bslib::layout_columns(col_widths = bslib::breakpoints(sm = 12, lg = c(6, 6)),
      bslib::card(full_screen = TRUE,
        bslib::card_header(htmltools::div(class = "rp-card-title", "Do sales differ when it is out of stock?",
                                          htmltools::span(class = "rp-sub", "Mean recorded sales per trading hour, in stock vs out of stock"))),
        plotly::plotlyOutput(ns("inout"), height = "280px"), shiny::uiOutput(ns("inout_note"))),
      bslib::card(
        bslib::card_header(htmltools::div(class = "rp-card-title", "How does it compare?",
                                          htmltools::span(class = "rp-sub", "This product vs its category median (and the comparison product)"))),
        reactable::reactableOutput(ns("compare_tbl")),
        shiny::uiOutput(ns("risk_expl")))
    )
  )
}

mod_product_server <- function(id, RP, state, anoms_r, recs_r) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns
    rng <- range(RP$daily$dt)
    shiny::updateDateRangeInput(session, "range", start = rng[1], end = rng[2], min = rng[1], max = rng[2])

    # keep the selector and the shared state in sync
    shiny::observeEvent(state$product, {
      if (!identical(as.character(state$product), input$product))
        shiny::updateSelectizeInput(session, "product", selected = state$product)
    }, ignoreNULL = TRUE)
    shiny::observeEvent(input$product, { if (nzchar(input$product)) state$product <- as.integer(input$product) }, ignoreInit = TRUE)
    shiny::observeEvent(state$date, {
      if (!is.null(state$date) && !is.na(state$date))
        shiny::updateDateRangeInput(session, "range", start = max(rng[1], state$date - 28), end = min(rng[2], state$date + 14))
    }, ignoreNULL = TRUE)
    shiny::observeEvent(input$horizon, state$horizon <- input$horizon)
    shiny::observeEvent(state$horizon, if (!identical(state$horizon, input$horizon)) shiny::updateSliderInput(session, "horizon", value = state$horizon))

    pid <- shiny::reactive({ shiny::req(input$product); as.integer(input$product) })
    dp <- shiny::reactive({
      x <- RP$daily[RP$daily$product_id == pid(), ]
      r <- input$range
      if (length(r) == 2 && !any(is.na(r))) x <- x[x$dt >= r[1] & x$dt <= r[2], ]
      x
    })
    fcp <- shiny::reactive({
      if (!isTRUE(input$show_fc)) return(NULL)
      f <- RP$forecast_next[RP$forecast_next$product_id == pid() & RP$forecast_next$.model == RP$manifest$chosen_model, ]
      f
    })
    prod_row <- shiny::reactive(RP$products[RP$products$product_id == pid(), ])

    output$horizon_note <- shiny::renderUI({
      if (input$horizon > RP$manifest$evaluated_horizon)
        htmltools::div(class = "rp-warn", sprintf("Days %d–%d are beyond the %d-day horizon that was evaluated; treat them with extra caution.",
                                                   RP$manifest$evaluated_horizon + 1, input$horizon, RP$manifest$evaluated_horizon))
    })

    output$header <- shiny::renderUI({
      pr <- prod_row(); shiny::req(nrow(pr) == 1)
      recs <- recs_r(); r <- recs[recs$product_id == pid(), ]
      rel <- if (nrow(r)) r$reliability[1] else "–"
      risk <- RP$risk_next$risk[RP$risk_next$product_id == pid()]
      x <- dp()
      so_days <- sum(x$stock_h >= 4); unmet <- sum(x$lost) / max(sum(x$latent), 1e-9)
      rk <- if (length(risk) && !is.na(risk)) risk else NA
      htmltools::tagList(htmltools::div(class = "rp-prod-head",
        htmltools::div(htmltools::h2(pr$label), htmltools::span(class = "rp-sub", sprintf("%s · encoded product ID %s · the dataset does not include product names", pr$category, pr$product_id))),
        htmltools::div(class = "rp-chips",
          rp_badge(paste("Forecast reliability:", rel), c(High = "good", Medium = "neutral", Low = "warning", "–" = "neutral")[[rel]]),
          rp_badge(sprintf("Next-day stockout risk: %s", fmt_pct(risk)), if (length(risk) && !is.na(risk) && risk >= RP$manifest$risk_threshold) "critical" else "neutral"))),
        htmltools::div(class = "rp-mini-kpis",
          rp_kpi("Recorded sales", fmt_num(sum(x$sale_amount), 1), sprintf("%s – %s", format(min(x$dt), "%d %b"), format(max(x$dt), "%d %b")), "cart-shopping"),
          rp_kpi("Estimated demand", fmt_num(sum(x$latent), 1), "recorded + estimated lost sales", "chart-column"),
          rp_kpi("Unmet demand", fmt_pct(unmet, 1), "share of estimated demand", "box-open", tone_for(unmet, 0.05, 0.15)),
          rp_kpi("Stockout days", sprintf("%d / %d", so_days, nrow(x)), "days with 4+ trading hours out", "store-slash", tone_for(so_days / max(nrow(x), 1), 0.15, 0.35)),
          rp_kpi("Next-day risk", fmt_pct(rk), sprintf("model threshold %s", fmt_pct(RP$manifest$risk_threshold)), "triangle-exclamation",
                 if (is.na(rk)) "neutral" else if (rk >= RP$manifest$risk_threshold) "critical" else "good")))
    })

    output$trend <- plotly::renderPlotly({
      x <- dp(); if (!nrow(x)) return(rp_empty_plot("No days in the selected range"))
      a <- anoms_r(); a <- a[a$product_id == pid() & a$dt >= min(x$dt) & a$dt <= max(x$dt), ]
      f <- if (max(x$dt) == max(RP$daily$dt)) fcp() else NULL
      cmp <- NULL; cl <- NULL
      if (nzchar(input$compare %||% "") && as.integer(input$compare) != pid()) {
        cmp <- RP$daily[RP$daily$product_id == as.integer(input$compare) & RP$daily$dt >= min(x$dt) & RP$daily$dt <= max(x$dt), ]
        cl <- plabel(input$compare)
      }
      ch_trend(x, a, f, input$horizon, cmp, cl)
    })
    output$trend_note <- shiny::renderUI({
      x <- dp(); shiny::req(nrow(x))
      so <- sum(x$stock_h >= 4); lost <- sum(x$lost); tot <- sum(x$latent)
      rp_note(sprintf("In this range, %s had 4+ stockout hours on %d of %d days. Estimated unmet demand is %s units (%s of estimated demand). ",
                      plabel(pid()), so, nrow(x), fmt_num(lost, 2), fmt_pct(lost / max(tot, 1e-9), 1)),
              if (isTRUE(input$show_fc) && max(x$dt) == max(RP$daily$dt)) sprintf("The dashed line is a %s forecast of estimated demand for the next %d days, with its 80%% interval.",
                                                                                 toupper(RP$manifest$chosen_model), input$horizon) else "")
    })

    output$recs <- shiny::renderUI({
      r <- recs_r(); r <- r[r$product_id == pid(), ]
      if (!nrow(r)) return(NULL)
      cards <- lapply(seq_len(nrow(r)), function(i) htmltools::div(class = paste("rp-rec", paste0("rp-rec-", urgency_kind(r$urgency[i]))),
        htmltools::div(class = "rp-rec-top", htmltools::strong(r$action[i]), rp_badge(r$urgency[i], urgency_kind(r$urgency[i])),
                       rp_badge(r$recommendation_type[i], if (r$recommendation_type[i] == "Data-supported") "info" else "neutral")),
        htmltools::p(r$reason[i]),
        htmltools::p(class = "rp-rec-ev", htmltools::strong("Evidence: "), r$evidence[i]),
        if (nzchar(r$if_ignored[i])) htmltools::p(class = "rp-rec-ev", htmltools::strong("If ignored: "), r$if_ignored[i]),
        htmltools::p(class = "rp-rec-rule", r$rule[i], " · reliability: ", r$reliability[i])))
      bslib::card(bslib::card_header(htmltools::div(class = "rp-card-title", "Recommendations for this product",
                    htmltools::span(class = "rp-sub", "Rule-based; no order quantities (the dataset has no inventory, lead time or cost data)"))),
                  htmltools::div(class = "rp-rec-grid", cards))
    })

    output$wdh <- plotly::renderPlotly(ch_weekday_hour(RP$weekday_hour[RP$weekday_hour$product_id == pid(), ]))
    output$wdh_note <- shiny::renderUI({
      w <- RP$weekday_hour[RP$weekday_hour$product_id == pid(), ]; shiny::req(nrow(w))
      by_h <- stats::aggregate(mean_sales ~ hour, w, mean); by_d <- stats::aggregate(mean_sales ~ weekday, w, mean)
      rp_note(sprintf("Busiest hour on average: %02d:00. Busiest weekday: %s. Stockout hours are excluded, so these show demand while the product was available.",
                      by_h$hour[which.max(by_h$mean_sales)], c("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")[by_d$weekday[which.max(by_d$mean_sales)]]))
    })
    output$sellout <- plotly::renderPlotly({
      cur <- RP$sellout_curves[RP$sellout_curves$product_id == pid(), ]
      if (!nrow(cur) || all(cur$surv == 1)) return(rp_empty_plot("No trading-hour stockouts recorded for this product"))
      ch_sellout(cur)
    })
    output$sellout_note <- shiny::renderUI({
      s <- RP$sellout_summary[RP$sellout_summary$product_id == pid(), ]; shiny::req(nrow(s))
      rp_note(sprintf("It ran out during trading hours on %d of %d days (%s). %s Probability of still being in stock at 18:00: %s.",
                      s$sellout_days, s$days, fmt_pct(s$sellout_share),
                      if (is.na(s$median_sellout_hour)) "On most days it never sold out." else sprintf("On half of all days it was out by %02.0f:00.", s$median_sellout_hour),
                      fmt_pct(s$p_instock_18)))
    })
    output$inout <- plotly::renderPlotly({
      h <- RP$hourly[RP$hourly$product_id == pid() & RP$hourly$hour %in% 6:21, ]
      if (!nrow(h)) return(rp_empty_plot())
      x <- stats::aggregate(sales ~ hour + out, h, mean); names(x)[3] <- "mean_sales"
      x$status <- ifelse(x$out == 1, "Out of stock", "In stock")
      ch_instock_vs_out(x)
    })
    output$inout_note <- shiny::renderUI({
      h <- RP$hourly[RP$hourly$product_id == pid() & RP$hourly$hour %in% 6:21, ]; shiny::req(nrow(h))
      rp_note(sprintf("Recorded sales average %s per in-stock hour and %s per out-of-stock hour. Near-zero sales while out of stock are censored demand, not low demand.",
                      fmt_num(mean(h$sales[h$out == 0]), 3), fmt_num(mean(h$sales[h$out == 1]), 3)))
    })

    output$compare_tbl <- reactable::renderReactable({
      pr <- prod_row(); shiny::req(nrow(pr) == 1)
      cat_rows <- RP$products[RP$products$first_category_id == pr$first_category_id, ]
      metric <- function(row) c(row$mean_latent, row$cv, row$unmet_share, row$stockout_hour_rate, row$sellout_share)
      tb <- data.frame(Metric = c("Mean estimated demand / day", "Variability (CV)", "Unmet demand share", "Stockout-hour rate", "Days with a sell-out"),
                       This = metric(pr),
                       Category = c(stats::median(cat_rows$mean_latent), stats::median(cat_rows$cv), stats::median(cat_rows$unmet_share),
                                    stats::median(cat_rows$stockout_hour_rate), stats::median(cat_rows$sellout_share)))
      names(tb)[2] <- pr$label; names(tb)[3] <- "Category median"
      if (nzchar(input$compare)) {
        cp <- RP$products[RP$products$product_id == as.integer(input$compare), ]
        if (nrow(cp)) tb[[cp$label]] <- metric(cp)
      }
      fm <- function(v, i) if (i == 1) fmt_num(v, 2) else if (i == 2) fmt_num(v, 2) else fmt_pct(v, 1)
      cols <- setdiff(names(tb), "Metric")
      for (cc in cols) tb[[cc]] <- vapply(seq_len(nrow(tb)), function(i) fm(tb[[cc]][i], i), "")
      reactable::reactable(tb, compact = TRUE, sortable = FALSE)
    })

    output$risk_expl <- shiny::renderUI({
      rn <- RP$risk_next[RP$risk_next$product_id == pid(), ]; co <- RP$risk_coefficients
      if (!nrow(rn) || !nrow(co)) return(NULL)
      b <- stats::setNames(co$estimate, co$term)
      vars <- intersect(names(b), names(rn))
      contrib <- vapply(vars, function(v) b[[v]] * as.numeric(rn[[v]]), 0)
      top <- sort(contrib, decreasing = TRUE)[1:min(3, length(contrib))]
      nice <- c(so_rate7 = "recent stockout frequency", so_hours7 = "recent stockout hours", yest_event = "a stockout yesterday",
                demand_ratio = "recent demand change", promo = "promotion", holiday_flag = "holiday", weekend = "weekend")
      htmltools::div(class = "rp-risk",
        htmltools::strong(sprintf("Why is next-day stockout risk %s?", fmt_pct(rn$risk))),
        htmltools::p(sprintf("The largest upward contributions on the log-odds scale come from %s. ",
                             paste(unname(nice[names(top)]), collapse = ", ")),
                     sprintf("Estimated for %s, assuming no promotion or holiday that day. This reflects historical sell-out patterns, not current stock on hand (the dataset has no inventory field).",
                             format(rn$next_dt, "%a %d %b %Y"))))
    })

    output$facts <- shiny::renderUI({
      pr <- prod_row(); shiny::req(nrow(pr) == 1)
      ev <- RP$forecast_eval_product[RP$forecast_eval_product$product_id == pid(), ]
      cv <- RP$forecast_cv_product[RP$forecast_cv_product$product_id == pid() & RP$forecast_cv_product$.model == RP$manifest$chosen_model, ]
      spec <- RP$ets_spec$ets_form[RP$ets_spec$product_id == pid()]
      htmltools::div(class = "rp-facts",
        htmltools::div(htmltools::span("Fully in-stock days"), htmltools::strong(pr$full_instock_days)),
        htmltools::div(htmltools::span("Promotion days"), htmltools::strong(pr$promo_days)),
        htmltools::div(htmltools::span("CV WAPE (chosen model)"), htmltools::strong(fmt_pct(cv$WAPE, 1))),
        htmltools::div(htmltools::span("Hold-out WAPE ETS / naive"), htmltools::strong(sprintf("%s / %s", fmt_pct(ev$WAPE[ev$.model == "ets"], 0), fmt_pct(ev$WAPE[ev$.model == "snaive"], 0)))),
        htmltools::div(htmltools::span("ETS form"), htmltools::strong(if (length(spec)) spec else "–")))
    })
  })
}
