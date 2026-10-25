# Page 5 - Data quality and methods -----------------------------------------------------------------

mod_methods_ui <- function(id, choices) {
  ns <- shiny::NS(id)
  bslib::navset_card_tab(
    bslib::nav_panel("Data preparation",
      shiny::uiOutput(ns("dq_kpis")),
      bslib::layout_columns(col_widths = bslib::breakpoints(sm = 12, lg = c(5, 7)),
        bslib::card(bslib::card_header(htmltools::div(class = "rp-card-title", "Raw vs cleaned data")), reactable::reactableOutput(ns("dims")),
                    rp_note("Rows are product-days for the selected store; both the training (90 days) and evaluation (7 days) splits are included.")),
        bslib::card(bslib::card_header(htmltools::div(class = "rp-card-title", "Issues found and how they were treated")), reactable::reactableOutput(ns("issues")))),
      bslib::layout_columns(col_widths = bslib::breakpoints(sm = 12, lg = c(6, 6)),
        bslib::card(bslib::card_header(htmltools::div(class = "rp-card-title", "Missing values before and after cleaning")), reactable::reactableOutput(ns("missing"))),
        bslib::card(full_screen = TRUE, bslib::card_header(htmltools::div(class = "rp-card-title", "Before vs after: what estimating demand changes",
                    htmltools::span(class = "rp-sub", "Daily totals per product-day on days with any trading-hour stockout"))),
                    plotly::plotlyOutput(ns("before_after"), height = "280px"), shiny::uiOutput(ns("ba_note")))),
      bslib::card(bslib::card_header(htmltools::div(class = "rp-card-title", "Transformations and engineered features",
                  htmltools::span(class = "rp-sub", "All lag and rolling features use only days before the day being described"))),
                  reactable::reactableOutput(ns("features")))
    ),
    bslib::nav_panel("Exploratory analysis",
      bslib::layout_columns(col_widths = bslib::breakpoints(sm = 12, lg = c(6, 6)),
        bslib::card(full_screen = TRUE, bslib::card_header(htmltools::div(class = "rp-card-title", "When does the store sell?",
                    htmltools::span(class = "rp-sub", "Mean recorded sales per in-stock product-hour, all products"))),
                    plotly::plotlyOutput(ns("store_wdh"), height = "300px"), shiny::uiOutput(ns("wdh_note"))),
        bslib::card(full_screen = TRUE, bslib::card_header(htmltools::div(class = "rp-card-title", "How much do stockouts suppress recorded sales?",
                    htmltools::span(class = "rp-sub", "Mean recorded sales per trading hour, in stock vs out of stock"))),
                    plotly::plotlyOutput(ns("inout"), height = "300px"), shiny::uiOutput(ns("inout_note")))),
      bslib::card(full_screen = TRUE, bslib::card_header(htmltools::div(class = "rp-card-title", "Which products are volatile, and which lose the most demand?",
                  htmltools::span(class = "rp-sub", "Each dot is a product; size and colour = estimated unmet share"))),
                  plotly::plotlyOutput(ns("variab"), height = "340px"), shiny::uiOutput(ns("var_note")))
    ),
    bslib::nav_panel("Models and evaluation",
      htmltools::h5(class = "rp-sec", "1 · Stockout-aware demand estimation"),
      bslib::layout_columns(col_widths = bslib::breakpoints(sm = 12, lg = c(4, 4, 4)),
        bslib::card(reactable::reactableOutput(ns("lat_tbl")), shiny::uiOutput(ns("lat_note"))),
        bslib::card(full_screen = TRUE, plotly::plotlyOutput(ns("lat_cut"), height = "260px")),
        bslib::card(full_screen = TRUE, plotly::plotlyOutput(ns("lat_sc"), height = "260px"))),
      htmltools::h5(class = "rp-sec", "2 · Demand forecasting"),
      bslib::layout_columns(col_widths = bslib::breakpoints(sm = 12, lg = c(6, 6)),
        bslib::card(reactable::reactableOutput(ns("fc_tbl")), shiny::uiOutput(ns("fc_note"))),
        bslib::card(full_screen = TRUE, plotly::plotlyOutput(ns("fc_bars"), height = "300px"))),
      bslib::card(full_screen = TRUE, bslib::card_header(htmltools::div(class = "rp-card-title", "Forecast vs actual in the evaluation week",
                  shiny::selectizeInput(ns("fc_prod"), NULL, choices = choices, width = "260px"))),
                  plotly::plotlyOutput(ns("fc_avf"), height = "280px"),
                  rp_note("Hollow red markers are days with a stockout; they are excluded from scoring because recorded sales understate demand.")),
      htmltools::h5(class = "rp-sec", "3 · Next-day stockout risk"),
      bslib::layout_columns(col_widths = bslib::breakpoints(sm = 12, lg = c(7, 5)),
        bslib::card(reactable::reactableOutput(ns("risk_tbl")), shiny::uiOutput(ns("risk_note"))),
        bslib::card(htmltools::div(class = "rp-card-title", "Confusion matrix · evaluation week"), shiny::uiOutput(ns("confusion")))),
      bslib::layout_columns(col_widths = bslib::breakpoints(sm = 12, lg = c(6, 6)),
        bslib::card(full_screen = TRUE, bslib::card_header(htmltools::div(class = "rp-card-title", "Are predicted probabilities trustworthy?")),
                    plotly::plotlyOutput(ns("calib"), height = "280px")),
        bslib::card(full_screen = TRUE, bslib::card_header(htmltools::div(class = "rp-card-title", "What drives the risk score?")),
                    plotly::plotlyOutput(ns("coefs"), height = "280px"))),
      htmltools::h5(class = "rp-sec", "4 · Anomaly detection and decision rules"),
      bslib::card(shiny::uiOutput(ns("rules")))
    ),
    bslib::nav_panel("Dataset and limitations", shiny::uiOutput(ns("dataset")))
  )
}

mod_methods_server <- function(id, RP, state) {
  shiny::moduleServer(id, function(input, output, session) {
    q <- RP$quality; m <- RP$manifest
    rt <- function(df, ...) reactable::reactable(df, compact = TRUE, sortable = FALSE, ...)

    output$dq_kpis <- shiny::renderUI({
      mb <- unlist(q$raw_profile$missing_by_column)
      imputed <- sum(unlist(q[c("imputed_precpt", "imputed_avg_temperature", "imputed_avg_humidity", "imputed_avg_wind_level")]), na.rm = TRUE)
      issues <- sum(unlist(q[c("duplicates_removed", "hourly_wrong_length", "hourly_daily_mismatch", "negative_sales_rows", "discount_out_of_range", "stock_count_mismatch")]), na.rm = TRUE)
      htmltools::div(class = "rp-kpis",
        rp_kpi("Raw rows", fmt_num(q$raw_profile$rows, 0), sprintf("%s columns · %s products", q$raw_profile$columns, q$raw_profile$products), "database"),
        rp_kpi("Cleaned rows", fmt_num(q$rows_clean, 0), sprintf("%s to %s", q$date_min, q$date_max), "broom"),
        rp_kpi("Duplicates removed", q$duplicates_removed %||% 0, "duplicate product-days", "clone", if ((q$duplicates_removed %||% 0) > 0) "warning" else "good"),
        rp_kpi("Rows changed by checks", fmt_num(issues, 0), "length, sum, sign, discount and stock-count checks", "list-check", if (issues > 0) "warning" else "good"),
        rp_kpi("Missing values", fmt_num(sum(mb, na.rm = TRUE), 0), sprintf("%s weather values imputed with the store median", fmt_num(imputed, 0)), "circle-half-stroke",
               if (sum(mb, na.rm = TRUE) > 0) "warning" else "good"))
    })

    output$dims <- reactable::renderReactable(rt(data.frame(
      Item = c("Rows (product-days)", "Columns", "Products", "Date range", "Training / evaluation rows"),
      Raw = c(fmt_num(q$raw_profile$rows, 0), q$raw_profile$columns, q$raw_profile$products,
              paste(q$raw_profile$date_min, "to", q$raw_profile$date_max),
              paste(q$raw_profile$rows_by_split$train, "/", q$raw_profile$rows_by_split$eval)),
      Cleaned = c(fmt_num(q$rows_clean, 0), "Daily table + 24-hour matrices", q$products, paste(q$date_min, "to", q$date_max),
                  paste(sum(RP$daily$split == "train"), "/", sum(RP$daily$split == "eval"))))))

    output$issues <- reactable::renderReactable(rt(data.frame(
      Check = c("Duplicate product-days", "Hourly lists not of length 24", "Hourly sum ≠ daily sale_amount (> 0.05)", "Negative sales values",
                "Discount outside (0, 1]", "stock_hour6_22_cnt ≠ recount from hourly status", "Missing product-days in the calendar"),
      Found = c(q$duplicates_removed, q$hourly_wrong_length, q$hourly_daily_mismatch, q$negative_sales_rows, q$discount_out_of_range,
                q$stock_count_mismatch, q$missing_product_days),
      Treatment = c("Kept first occurrence", "Row removed", "Daily total replaced by the hourly sum (hourly record treated as authoritative)",
                    "Set to 0", "Set to 1.0 (no discount)", "Recomputed from hourly status (hours 06–21)", "Reported; series kept as observed"))))

    output$missing <- reactable::renderReactable({
      mb <- q$raw_profile$missing_by_column
      imp <- c(precpt = q$imputed_precpt, avg_temperature = q$imputed_avg_temperature, avg_humidity = q$imputed_avg_humidity, avg_wind_level = q$imputed_avg_wind_level)
      after <- vapply(names(mb), function(n) if (n %in% names(imp)) 0L else as.integer(mb[[n]]), 0L)
      rt(data.frame(row.names = NULL, Column = names(mb), Before = unname(unlist(mb)), After = unname(after),
                    Treatment = ifelse(names(mb) %in% names(imp) & unlist(mb) > 0, "Imputed with store median", ifelse(unlist(mb) > 0, "Row-level check", "None needed"))),
         defaultPageSize = 8)
    })
    output$before_after <- plotly::renderPlotly({
      x <- RP$daily[RP$daily$any_stockout == 1, ]
      if (!nrow(x)) return(rp_empty_plot("No stockout days"))
      plotly::plot_ly() |>
        plotly::add_histogram(x = x$sale_amount, name = "Recorded sales", marker = list(color = RP_COL$recorded, opacity = 0.55), nbinsx = 40) |>
        plotly::add_histogram(x = x$latent, name = "Estimated demand", marker = list(color = RP_COL$demand, opacity = 0.55), nbinsx = 40) |>
        rp_plotly_layout(xtitle = "Daily total (normalised units)", ytitle = "Product-days", hovermode = "closest") |>
        plotly::layout(barmode = "overlay")
    })
    output$ba_note <- shiny::renderUI({
      x <- RP$daily[RP$daily$any_stockout == 1, ]; shiny::req(nrow(x))
      rp_note(sprintf("On the %d product-days with any trading-hour stockout, the median daily total rises from %s (recorded) to %s (estimated demand). %d days used the profile method and %d the fallback level (in-stock share below %.0f%%).",
                      nrow(x), fmt_num(stats::median(x$sale_amount), 2), fmt_num(stats::median(x$latent), 2),
                      sum(x$latent_method == "profile"), sum(x$latent_method == "fallback"), 100 * m$thresholds$min_share_in))
    })
    output$features <- reactable::renderReactable(rt(as.data.frame(RP$feature_dictionary), columns = list(
      feature = reactable::colDef(name = "Feature", width = 170), definition = reactable::colDef(name = "Definition"),
      uses_future = reactable::colDef(name = "Uses future data?", width = 190))))

    output$store_wdh <- plotly::renderPlotly(ch_weekday_hour(RP$store_weekday_hour))
    output$wdh_note <- shiny::renderUI({
      w <- RP$store_weekday_hour; by_h <- stats::aggregate(mean_sales ~ hour, w, mean)
      top <- by_h$hour[order(-by_h$mean_sales)][1:2]
      rp_note(sprintf("The two busiest hours across the store are %02d:00 and %02d:00. Night hours (00–05) show near-zero sales.", top[1], top[2]))
    })
    output$inout <- plotly::renderPlotly(ch_instock_vs_out(RP$instock_vs_out))
    output$inout_note <- shiny::renderUI({
      x <- RP$instock_vs_out
      a <- stats::weighted.mean(x$mean_sales[x$status == "In stock"], x$hours[x$status == "In stock"])
      b <- stats::weighted.mean(x$mean_sales[x$status == "Out of stock"], x$hours[x$status == "Out of stock"])
      rp_note(sprintf("Recorded sales average %s per in-stock trading hour and %s per out-of-stock hour, so sales during stockouts are almost entirely missing. This is why recorded sales cannot be treated as demand.",
                      fmt_num(a, 3), fmt_num(b, 3)))
    })
    output$variab <- plotly::renderPlotly(ch_variability(RP$variability))
    output$var_note <- shiny::renderUI({
      v <- RP$variability
      rp_note(sprintf("Median coefficient of variation is %s. %d products lose more than 10%% of estimated demand to stockouts.",
                      fmt_num(stats::median(v$cv), 2), sum(v$unmet_share > 0.10)))
    })

    output$lat_tbl <- reactable::renderReactable({
      x <- as.data.frame(RP$latent_val$metrics)
      x$method <- c(profile_method = "Hourly-profile estimate", observed_only = "Observed sales only")[x$method]
      rt(data.frame(Method = x$method, MAE = fmt_num(x$MAE, 3), WAPE = fmt_pct(x$WAPE, 1), Bias = fmt_pct(x$bias, 1)))
    })
    output$lat_note <- shiny::renderUI(rp_note(sprintf(
      "Validation on %d fully in-stock training days: trading hours from a random cut-off (12:00–20:00) were hidden as if out of stock, then the day total was estimated with a profile that excludes that day (leave-one-out).",
      RP$latent_val$n)))
    output$lat_cut <- plotly::renderPlotly(ch_latent_cutoff(RP$latent_validation_by_cutoff))
    output$lat_sc <- plotly::renderPlotly(ch_latent_scatter(RP$latent_validation_rows))

    output$fc_tbl <- reactable::renderReactable({
      cv <- RP$forecast_cv_overall; ev <- RP$forecast_eval_overall
      x <- rbind(cbind(Window = "CV (4 origins, training)", cv), cbind(Window = "Hold-out (eval week)", ev))
      rt(data.frame(Window = x$Window, Model = ifelse(x$.model == "ets", "ETS", "Seasonal naive"), `In-stock days` = x$n_instock,
                    MAE = fmt_num(x$MAE, 3), RMSE = fmt_num(x$RMSE, 3), WAPE = fmt_pct(x$WAPE, 1), Bias = fmt_pct(x$bias, 1),
                    `80% coverage` = fmt_pct(x$coverage80, 0), `WAPE vs est. demand` = fmt_pct(x$WAPE_vs_latent, 1), check.names = FALSE))
    })
    output$fc_note <- shiny::renderUI({
      cv <- RP$forecast_cv_overall; ev <- RP$forecast_eval_overall
      better <- ev$WAPE[ev$.model == "ets"] < ev$WAPE[ev$.model == "snaive"]
      rp_note(sprintf("The model was chosen on training CV only (%s). On the untouched evaluation week, ETS %s the seasonal-naive baseline (WAPE %s vs %s). ",
                      toupper(m$chosen_model), if (better) "beats" else "does not beat", fmt_pct(ev$WAPE[ev$.model == "ets"], 1), fmt_pct(ev$WAPE[ev$.model == "snaive"], 1)),
              "Scores use in-stock days only. These are high-demand days less often (busy days sell out), so a positive bias is expected; WAPE is unstable for products with many zero-sale days.")
    })
    output$fc_bars <- plotly::renderPlotly(ch_model_bars(RP$forecast_cv_overall, RP$forecast_eval_overall))
    output$fc_avf <- plotly::renderPlotly({
      shiny::req(input$fc_prod)
      ch_actual_vs_fc(RP$forecast_eval[RP$forecast_eval$product_id == as.integer(input$fc_prod), ])
    })

    output$risk_tbl <- reactable::renderReactable({
      x <- as.data.frame(RP$risk_metrics)
      x$set <- c(logistic_validation = "Logistic · validation (threshold chosen here)", logistic_test = "Logistic · evaluation week",
                 frequency_baseline_test = "Frequency baseline · evaluation week")[x$set]
      rt(data.frame(Set = x$set, n = x$n, `Event rate` = fmt_pct(x$base_rate, 1), AUC = fmt_num(x$AUC, 3), Brier = fmt_num(x$brier, 3),
                    Precision = fmt_pct(x$precision, 0), Recall = fmt_pct(x$recall, 0), F1 = fmt_num(x$F1, 3), check.names = FALSE))
    })
    output$risk_note <- shiny::renderUI(rp_note(sprintf(
      "Target: %g+ of 16 trading hours out of stock tomorrow. Fit %s to %s, validation %s to %s, test %s to %s. Event rate in the fit window: %s, so accuracy alone would mislead; precision, recall and F1 are reported at threshold %.2f.",
      m$thresholds$risk_event_hours, m$risk_windows$fit[1], m$risk_windows$fit[2], m$risk_windows$validation[1], m$risk_windows$validation[2],
      m$risk_windows$test[1], m$risk_windows$test[2], fmt_pct(m$risk_class_balance$fit, 1), m$risk_threshold)))
    output$confusion <- shiny::renderUI({
      x <- RP$risk_metrics[RP$risk_metrics$set == "logistic_test", ]; shiny::req(nrow(x))
      cell <- function(v, lab, cls) htmltools::div(class = paste("rp-cm", cls), htmltools::strong(v), htmltools::span(lab))
      htmltools::div(class = "rp-cm-grid",
        htmltools::div(), htmltools::div(class = "rp-cm-h", "Predicted: event"), htmltools::div(class = "rp-cm-h", "Predicted: no event"),
        htmltools::div(class = "rp-cm-h", "Actual: event"), cell(x$TP, "true positive", "ok"), cell(x$FN, "missed", "bad"),
        htmltools::div(class = "rp-cm-h", "Actual: no event"), cell(x$FP, "false alarm", "bad"), cell(x$TN, "true negative", "ok"))
    })
    output$calib <- plotly::renderPlotly(ch_calibration(RP$risk_calibration))
    output$coefs <- plotly::renderPlotly(ch_coefs(RP$risk_coefficients))

    output$rules <- shiny::renderUI({
      r <- m$rules
      htmltools::div(class = "rp-rules",
        htmltools::p(htmltools::strong("Anomalies: "), sprintf("robust z-score of recorded sales against the product's weekday-adjusted median of the previous %d in-stock days (spread = 1.4826 × MAD, floored). Flag when |z| ≥ %.1f (current setting %.1f). A flag is labelled Stockout, Promotion, Holiday, Possibly heavy rain or Unexplained, using the day's recorded flags. There is no ground truth, so detection accuracy is not claimed.",
                                                            m$thresholds$baseline_window, m$thresholds$anomaly_z, state$zthr)),
        htmltools::p(htmltools::strong("Decision rules (thresholds are design choices, not proven boundaries):")),
        htmltools::tags$ul(
          htmltools::tags$li(sprintf("R1 Consider replenishing earlier: %g+ risk-event days in the last 7, or next-day risk ≥ model threshold and unmet share ≥ %.0f%%.", r$stockout_days_thr, 100 * r$lost_share_thr)),
          htmltools::tags$li("R2 Investigate unexplained sales drop: an Unexplained drop anomaly in the last 7 days."),
          htmltools::tags$li(sprintf("R3 Review possible demand surge: forecast for the next 7 days ≥ %.0f%% of the last 7 days' estimated demand, or an Unexplained surge.", 100 * r$surge_ratio)),
          htmltools::tags$li(sprintf("R4 Plan for lower demand: forecast ratio ≤ %.0f%% and reliability not Low.", 100 * r$decline_ratio)),
          htmltools::tags$li(sprintf("R5 Use caution: reliability Low (CV WAPE > %.0f%%, < %g fully in-stock days, or > 50%% zero-sale days).", 100 * r$wape_low_reliability, r$min_instock_days)),
          htmltools::tags$li("R6 Maintain current approach: no other rule fired.")),
        htmltools::p("Priority = urgency weight (High 3, Medium 2, Low 1, Info 0.5) × (1 + w₁·unmet share + w₂·risk + w₃·[recent unusual activity])."))
    })

    output$dataset <- shiny::renderUI({
      bslib::layout_columns(col_widths = bslib::breakpoints(sm = 12, lg = c(6, 6)),
        bslib::card(bslib::card_header("Dataset"),
          htmltools::tags$dl(class = "rp-dl",
            htmltools::tags$dt("Source"), htmltools::tags$dd(htmltools::a(href = "https://huggingface.co/datasets/Dingdong-Inc/FreshRetailNet-50K", target = "_blank", "FreshRetailNet-50K, Dingdong-Inc (Hugging Face)"),
                                                            " · Wang et al. (2025), arXiv:2505.16319"),
            htmltools::tags$dt("Licence"), htmltools::tags$dd("CC BY 4.0"),
            htmltools::tags$dt("Data used"), htmltools::tags$dd(m$mode_note),
            htmltools::tags$dt("Store analysed"), htmltools::tags$dd(sprintf("Store %s · %d products", m$store_id, m$products)),
            htmltools::tags$dt("Dates represented"), htmltools::tags$dd(sprintf("Training %s to %s · evaluation %s to %s", m$train_range[1], m$train_range[2], m$eval_range[1], m$eval_range[2])),
            htmltools::tags$dt("Granularity"), htmltools::tags$dd("Daily rows with 24 hourly sales values and 24 hourly stock-status flags"),
            htmltools::tags$dt("Results generated"), htmltools::tags$dd(sprintf("%s (pipeline runtime %.0f s, %s)", m$generated_at, m$runtime_seconds, m$r_version)))),
        bslib::card(bslib::card_header("Limitations"),
          htmltools::tags$ul(
            htmltools::tags$li("Sales are globally normalised by an undisclosed factor, so every value is in normalised units: no money, kilograms or real quantities."),
            htmltools::tags$li("There is no inventory, price, cost, lead-time or shelf-life field. No reorder quantities, dates or financial losses are produced."),
            htmltools::tags$li("Hourly stock status = 1 is documented as out of stock. Overnight 1s may also mean closed or not stocked; only 06:00–21:59 is used for stockout analysis."),
            htmltools::tags$li("Estimated demand assumes a stable hourly sales profile. Its error is measured by the hidden-hours validation, and it is always labelled as an estimate."),
            htmltools::tags$li("90 training days: weekly patterns only, no yearly seasonality. Forecasts beyond 7 days were not evaluated."),
            htmltools::tags$li("Stores belong to one large operator; results are a proxy for a small independent shop."),
            htmltools::tags$li("Promotion effects are observational associations, not causal effects."),
            htmltools::tags$li("The monitoring page replays historical data; it is not connected to a live feed."))))
    })
  })
}
