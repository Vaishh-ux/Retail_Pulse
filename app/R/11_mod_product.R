# Page 2 - Product Demand ----------------------------------------------------------------------
# One product at a time: history of recorded sales vs estimated demand, a 7- or 14-day
# forecast with its 80% range, a plain-language reading, and the rule-based suggestions.
# Technical extras (weekday x hour pattern, sell-out curve, category comparison, model
# details) sit in a collapsible "More about this product" section and render only when opened.

mod_product_ui <- function(id, choices) {
  ns <- shiny::NS(id)
  htmltools::tagList(
    htmltools::div(class = "rp-hero",
      htmltools::div(htmltools::div(class = "rp-eyebrow", "Product demand"), htmltools::h1("How is this product doing?"),
                     htmltools::p("Pick a product to see its sales, the demand hidden by stockouts, and what to expect next.")),
      htmltools::div(class = "rp-filters",
        shiny::selectizeInput(ns("product"), "Product", choices = choices, width = "260px", options = list(placeholder = "Type a product ID, e.g. 108")),
        shiny::selectInput(ns("window"), "Show history", width = "150px", selected = "56",
                           choices = c("Last 4 weeks" = "28", "Last 8 weeks" = "56", "All data" = "all")),
        shiny::radioButtons(ns("horizon"), "Forecast", choices = c("7 days" = "7", "14 days" = "14"), selected = "7", inline = TRUE))),
    shiny::uiOutput(ns("header")),
    shiny::uiOutput(ns("linked")),
    bslib::layout_columns(col_widths = bslib::breakpoints(sm = 12, lg = c(8, 4)),
      bslib::card(full_screen = TRUE,
        bslib::card_header(rp_card_title("Sales, estimated demand and forecast", "gold shading = promotion · red bars = hours out of stock · dashed = forecast", "chart-line")),
        plotly::plotlyOutput(ns("trend"), height = "420px")),
      bslib::card(
        bslib::card_header(rp_card_title("What the forecast says", NULL, "bullseye")),
        shiny::uiOutput(ns("reading")))),
    shiny::uiOutput(ns("recs")),
    bslib::accordion(id = ns("more"), open = FALSE, class = "rp-accordion",
      bslib::accordion_panel("More about this product", value = "more", icon = shiny::icon("magnifying-glass-chart"),
        bslib::layout_columns(col_widths = bslib::breakpoints(sm = 12, lg = c(6, 6)),
          htmltools::div(htmltools::h6(class = "rp-mini-h", "When do customers buy it?"), plotly::plotlyOutput(ns("wdh"), height = "270px"), shiny::uiOutput(ns("wdh_note"))),
          htmltools::div(htmltools::h6(class = "rp-mini-h", "By what time does it usually run out?"), plotly::plotlyOutput(ns("sellout"), height = "270px"), shiny::uiOutput(ns("sellout_note")))),
        bslib::layout_columns(col_widths = bslib::breakpoints(sm = 12, lg = c(6, 6)),
          htmltools::div(htmltools::h6(class = "rp-mini-h", "Compared with its category"), reactable::reactableOutput(ns("compare"))),
          htmltools::div(htmltools::h6(class = "rp-mini-h", "Model details"), shiny::uiOutput(ns("facts"))))))
  )
}

mod_product_server <- function(id, RP, state, recs_r, anoms_r, catalogue = shiny::reactive(NULL), goto_simulator = function(sku) NULL) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns
    last_dt <- max(RP$daily$dt)
    sid <- as.character(RP$manifest$store_id)   # outputs below are cached across visitors per (store, product, view)
    shiny::observeEvent(state$product, {
      if (!identical(as.character(state$product), input$product)) shiny::updateSelectizeInput(session, "product", selected = state$product)
    }, ignoreNULL = TRUE)
    shiny::observeEvent(input$product, if (nzchar(input$product)) state$product <- as.integer(input$product), ignoreInit = TRUE)
    shiny::observeEvent(state$date, if (!is.null(state$date)) shiny::updateSelectInput(session, "window", selected = "all"), ignoreNULL = TRUE)

    pid <- shiny::reactive({ shiny::req(input$product); as.integer(input$product) })
    horizon <- shiny::reactive(as.integer(input$horizon %||% "7"))
    dp <- shiny::reactive({
      x <- RP$daily[RP$daily$product_id == pid(), ]
      w <- input$window %||% "56"
      if (w != "all") x <- x[x$dt > last_dt - as.integer(w), ]
      x
    })
    fc <- shiny::reactive({
      f <- RP$forecast_next[RP$forecast_next$product_id == pid() & RP$forecast_next$.model == RP$manifest$chosen_model, ]
      f[order(f$dt), ]
    })
    recs <- shiny::reactive({ r <- recs_r(); r[r$product_id == pid(), ] })

    output$header <- shiny::renderUI({
      pr <- RP$products[RP$products$product_id == pid(), ]; shiny::req(nrow(pr) == 1)
      x <- dp(); r <- recs()
      rel <- if (nrow(r)) r$reliability[1] else "–"
      risk <- RP$risk_next$risk[RP$risk_next$product_id == pid()]; risk <- if (length(risk)) risk else NA
      so_days <- sum(x$stock_h >= 4); unmet <- sum(x$lost) / max(sum(x$latent), 1e-9)
      htmltools::tagList(
        htmltools::div(class = "rp-prod-head",
          htmltools::div(htmltools::h2(pr$label), htmltools::span(class = "rp-sub", sprintf("%s · product names are not included in the dataset", pr$category))),
          htmltools::div(class = "rp-chips", rp_badge(paste("Forecast reliability:", rel), c(High = "good", Medium = "neutral", Low = "warning", "–" = "neutral")[[rel]]))),
        htmltools::div(class = "rp-mini-kpis",
          rp_kpi("Recorded sales", fmt_num(sum(x$sale_amount), 1), sprintf("%s – %s", format(min(x$dt), "%d %b"), format(max(x$dt), "%d %b")), "cart-shopping"),
          rp_kpi("Estimated demand", fmt_num(sum(x$latent), 1), "including sales missed while out of stock", "chart-column"),
          rp_kpi("Demand missed", fmt_pct(unmet, 1), sprintf("out of stock 4+ hours on %d of %d days", so_days, nrow(x)), "box-open", tone_for(unmet, 0.05, 0.15)),
          rp_kpi("Chance of a stockout tomorrow", fmt_pct(risk), "from past sell-out patterns, not current stock",
                 "triangle-exclamation", if (is.na(risk)) "neutral" else if (risk >= RP$manifest$risk_threshold) "critical" else "good")))
    }) |> shiny::bindCache(sid, pid(), input$window %||% "56", "header")

    # not cached: depends on this visitor's own catalogue
    output$linked <- shiny::renderUI({
      x <- catalogue(); if (is.null(x) || !nrow(x)) return(NULL)
      x <- x[!is.na(x$linked_product_id) & x$linked_product_id == pid(), , drop = FALSE]; if (!nrow(x)) return(NULL)
      htmltools::div(class = "rp-info-banner rp-linked", shiny::icon("boxes-stacked"), htmltools::div(
        htmltools::strong("Linked in your catalogue: "),
        lapply(seq_len(nrow(x)), function(i) htmltools::span(class = "rp-linked-item", sprintf("%s (%s) · %s in stock", x$name[i], x$sku[i], fmt_num(x$stock[i], 0)),
          htmltools::tags$button(type = "button", class = "btn btn-outline-secondary btn-xs", `data-rp-input` = ns("simulate"), `data-rp-value` = x$sku[i], "Simulate"))),
        htmltools::span(class = "rp-sub", " Your own store data; the charts below are historical research data in normalised units.")))
    })
    shiny::observeEvent(input$simulate, goto_simulator(input$simulate$value))

    output$trend <- plotly::renderPlotly({
      x <- dp(); if (!nrow(x)) return(rp_empty_plot("No days to show"))
      a <- anoms_r(); a <- a[a$product_id == pid() & a$dt >= min(x$dt), ]
      ch_trend(x, a, fc(), horizon())
    }) |> shiny::bindCache(sid, pid(), input$window %||% "56", horizon(), "trend")

    output$reading <- shiny::renderUI({
      f <- utils::head(fc(), horizon()); shiny::req(nrow(f))
      x <- RP$daily[RP$daily$product_id == pid(), ]
      last7 <- sum(x$latent[x$dt > last_dt - 7]); f7 <- sum(utils::head(f$mean, 7))
      ratio <- f7 / max(last7, 1e-9)
      r <- recs(); rel <- if (nrow(r)) r$reliability[1] else "Low"
      cv <- RP$forecast_cv_product$WAPE[RP$forecast_cv_product$product_id == pid() & RP$forecast_cv_product$.model == RP$manifest$chosen_model]
      trend_txt <- if (ratio >= 1.1) sprintf("about %s more than", fmt_pct(ratio - 1, 0)) else if (ratio <= 0.9) sprintf("about %s less than", fmt_pct(1 - ratio, 0)) else "about the same as"
      htmltools::div(class = "rp-reading",
        htmltools::div(class = "rp-big", fmt_num(sum(f$mean), 1), htmltools::span(sprintf(" units expected over the next %d days", nrow(f)))),
        htmltools::p(sprintf("For the next 7 days that is %s the estimated demand of the last 7 days (%s).", trend_txt, fmt_num(last7, 1))),
        htmltools::p(sprintf("On a typical day the forecast expects %s, and 8 times out of 10 the real value should fall between %s and %s.",
                             fmt_num(mean(f$mean), 2), fmt_num(mean(f$lo80), 2), fmt_num(mean(f$hi80), 2))),
        htmltools::p(htmltools::strong("How much to trust it: "), switch(rel,
          High = "good. This product's past forecasts were usually close.",
          Medium = "moderate. Past forecasts were sometimes off; use it as a guide.",
          "low. This product has little in-stock history or erratic sales; rely on your own judgement."),
          if (length(cv) && !is.na(cv)) sprintf(" (past forecast error %s)", fmt_pct(cv, 0))),
        if (horizon() > RP$manifest$evaluated_horizon) htmltools::div(class = "rp-warn", sprintf("Only the first %d days were tested; days %d–%d are less certain.",
                                                                                                 RP$manifest$evaluated_horizon, RP$manifest$evaluated_horizon + 1, horizon())),
        htmltools::p(class = "rp-sub", sprintf("Method: %s exponential smoothing on estimated demand, chosen because it beat a simple same-day-last-week forecast. A forecast is an estimate, not a guarantee.",
                                               toupper(RP$manifest$chosen_model))))
    }) |> shiny::bindCache(sid, pid(), horizon(), "reading")

    output$recs <- shiny::renderUI({
      r <- recs(); if (!nrow(r)) return(NULL)
      cards <- lapply(seq_len(nrow(r)), function(i) htmltools::div(class = paste("rp-rec", paste0("rp-rec-", urgency_kind(r$urgency[i]))),
        htmltools::div(class = "rp-rec-top", htmltools::strong(r$action[i]), rp_badge(r$urgency[i], urgency_kind(r$urgency[i]))),
        htmltools::p(r$reason[i]),
        if (nzchar(r$if_ignored[i])) htmltools::p(class = "rp-rec-ev", htmltools::strong("If nothing changes: "), r$if_ignored[i]),
        htmltools::p(class = "rp-rec-rule", "Evidence: ", r$evidence[i], " · ", r$rule[i])))
      bslib::card(bslib::card_header(rp_card_title("Suggested actions for this product", "rule-based · no order quantities (the data has no stock levels or costs)", "list-check")),
                  htmltools::div(class = "rp-rec-grid", cards))
    }) |> shiny::bindCache(sid, pid(), "recs")

    # details: rendered only while the accordion is open
    more_open <- shiny::reactive("more" %in% (input$more %||% character()))
    output$wdh <- plotly::renderPlotly({ shiny::req(more_open()); ch_weekday_hour(RP$weekday_hour[RP$weekday_hour$product_id == pid(), ]) })
    output$wdh_note <- shiny::renderUI({
      shiny::req(more_open())
      w <- RP$weekday_hour[RP$weekday_hour$product_id == pid(), ]; shiny::req(nrow(w))
      by_h <- stats::aggregate(mean_sales ~ hour, w, mean); by_d <- stats::aggregate(mean_sales ~ weekday, w, mean)
      rp_note(sprintf("Darker = more sales per hour while in stock. Busiest: %s around %02d:00.",
                      c("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")[by_d$weekday[which.max(by_d$mean_sales)]], by_h$hour[which.max(by_h$mean_sales)]))
    })
    output$sellout <- plotly::renderPlotly({
      shiny::req(more_open())
      cur <- RP$sellout_curves[RP$sellout_curves$product_id == pid(), ]
      if (!nrow(cur) || all(cur$surv == 1)) return(rp_empty_plot("This product did not run out during opening hours"))
      ch_sellout(cur)
    })
    output$sellout_note <- shiny::renderUI({
      shiny::req(more_open())
      s <- RP$sellout_summary[RP$sellout_summary$product_id == pid(), ]; shiny::req(nrow(s))
      rp_note(sprintf("Share of days the product was still on the shelf at each hour (Kaplan–Meier). It ran out on %d of %d days; %s Chance of still being in stock at 18:00: %s.",
                      s$sellout_days, s$days, if (is.na(s$median_sellout_hour)) "on most days it lasted all day." else sprintf("on half of all days it was gone by %02.0f:00.", s$median_sellout_hour),
                      fmt_pct(s$p_instock_18)))
    })
    output$compare <- reactable::renderReactable({
      shiny::req(more_open())
      pr <- RP$products[RP$products$product_id == pid(), ]; shiny::req(nrow(pr) == 1)
      cat_rows <- RP$products[RP$products$first_category_id == pr$first_category_id, ]
      v <- function(row) c(row$mean_latent, row$cv, row$unmet_share, row$stockout_hour_rate, row$sellout_share)
      med <- c(stats::median(cat_rows$mean_latent), stats::median(cat_rows$cv), stats::median(cat_rows$unmet_share),
               stats::median(cat_rows$stockout_hour_rate), stats::median(cat_rows$sellout_share))
      fm <- function(x) c(fmt_num(x[1], 2), fmt_num(x[2], 2), fmt_pct(x[3], 1), fmt_pct(x[4], 1), fmt_pct(x[5], 1))
      tb <- data.frame(Measure = c("Estimated demand per day", "Day-to-day variability (CV)", "Demand missed", "Hours out of stock", "Days it sold out"),
                       This = fm(v(pr)), Category = fm(med))
      names(tb)[2:3] <- c(pr$label, sprintf("%s median (%d products)", pr$category, nrow(cat_rows)))
      reactable::reactable(tb, compact = TRUE, sortable = FALSE)
    })
    output$facts <- shiny::renderUI({
      shiny::req(more_open())
      pr <- RP$products[RP$products$product_id == pid(), ]; shiny::req(nrow(pr) == 1)
      ev <- RP$forecast_eval_product[RP$forecast_eval_product$product_id == pid(), ]
      cv <- RP$forecast_cv_product[RP$forecast_cv_product$product_id == pid() & RP$forecast_cv_product$.model == RP$manifest$chosen_model, ]
      spec <- RP$ets_spec$ets_form[RP$ets_spec$product_id == pid()]
      rn <- RP$risk_next[RP$risk_next$product_id == pid(), ]
      htmltools::tagList(htmltools::div(class = "rp-facts",
        htmltools::div(htmltools::span("Days fully in stock"), htmltools::strong(pr$full_instock_days)),
        htmltools::div(htmltools::span("Days on promotion"), htmltools::strong(pr$promo_days)),
        htmltools::div(htmltools::span("Forecast error, cross-validation (WAPE)"), htmltools::strong(fmt_pct(cv$WAPE, 1))),
        htmltools::div(htmltools::span("Forecast error, held-out week: ETS / simple"), htmltools::strong(sprintf("%s / %s", fmt_pct(ev$WAPE[ev$.model == "ets"], 0), fmt_pct(ev$WAPE[ev$.model == "snaive"], 0)))),
        htmltools::div(htmltools::span("ETS model form"), htmltools::strong(if (length(spec)) spec else "–"))),
        if (nrow(rn)) rp_note(sprintf("Tomorrow's stockout chance (%s, for %s) comes from a logistic regression on the last 7 days' stockouts, yesterday's stockout and recent demand change; it assumes no promotion or holiday.",
                                      fmt_pct(rn$risk), format(rn$next_dt, "%d %b %Y"))))
    })
  })
}
