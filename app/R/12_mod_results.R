# Page 3 - Data & Model Results ----------------------------------------------------------------
# Evidence for the assessment: data preparation, exploration, forecasting method and
# evaluation, stockout-risk evaluation and CSV downloads of the analytical results.
# Detailed technical charts sit under "Advanced details". Shiny only renders outputs on the
# tab that is open, so the heavier charts cost nothing until someone opens their tab.

mod_results_ui <- function(id, RP) {
  ns <- shiny::NS(id)
  card <- function(title, sub, ...) bslib::card(full_screen = TRUE, bslib::card_header(rp_card_title(title, sub)), ...)
  two <- function(...) bslib::layout_columns(col_widths = bslib::breakpoints(sm = 12, lg = c(6, 6)), ...)
  htmltools::tagList(
    htmltools::div(class = "rp-hero", htmltools::div(htmltools::div(class = "rp-eyebrow", "Data & model results"),
      htmltools::h1("How the numbers were produced"),
      htmltools::p("Cleaning, exploration, the forecasting method and how well it worked, the stockout-risk model, and the results as CSV files."))),
    bslib::navset_card_underline(id = ns("tab"),
      bslib::nav_panel("Data preparation", value = "prep",
        shiny::uiOutput(ns("dq_kpis")),
        two(card("Raw vs cleaned data", NULL, reactable::reactableOutput(ns("dims")),
                 rp_note("Rows are product-days for this store: 90 training days plus a 7-day evaluation week.")),
            card("Checks and how problems were treated", NULL, reactable::reactableOutput(ns("issues")))),
        two(card("Missing values before and after cleaning", NULL, reactable::reactableOutput(ns("missing"))),
            card("What estimating demand changes", "Daily totals on days with any stockout", plotly::plotlyOutput(ns("before_after"), height = "280px"), shiny::uiOutput(ns("ba_note")))),
        card("Features created for the models", "Lags and rolling averages use only earlier days, so the models never see the future", reactable::reactableOutput(ns("features")))),
      bslib::nav_panel("Exploring the data", value = "eda",
        two(card("When does the store sell?", "Average sales per in-stock product-hour", plotly::plotlyOutput(ns("store_wdh"), height = "300px"), shiny::uiOutput(ns("wdh_note"))),
            card("Sales almost stop when a product is out of stock", "Average sales per opening hour", plotly::plotlyOutput(ns("inout"), height = "300px"), shiny::uiOutput(ns("inout_note")))),
        two(card("Categories: sold vs missed", "Whole period, 12 largest categories", plotly::plotlyOutput(ns("cats"), height = "340px")),
            card("Which products are volatile and which lose the most?", "Each dot is a product; bigger and redder = more demand missed", plotly::plotlyOutput(ns("variab"), height = "340px"), shiny::uiOutput(ns("var_note"))))),
      bslib::nav_panel("Forecasting", value = "fc",
        bslib::card(bslib::card_header(rp_card_title("Method", NULL)), shiny::uiOutput(ns("fc_method"))),
        card("How accurate were the forecasts?", "Lower error is better; scored on in-stock days only", reactable::reactableOutput(ns("fc_tbl")), shiny::uiOutput(ns("fc_note"))),
        bslib::layout_columns(col_widths = bslib::breakpoints(sm = 12, lg = c(5, 7)),
          card("Error by model", "WAPE = average error as a share of actual sales", plotly::plotlyOutput(ns("fc_bars"), height = "300px")),
          bslib::card(full_screen = TRUE, bslib::card_header(htmltools::div(class = "rp-card-title", "Forecast vs actual in the held-out week",
                      shiny::selectizeInput(ns("fc_prod"), NULL, choices = RP$product_choices, width = "240px"))),
                      plotly::plotlyOutput(ns("fc_avf"), height = "280px"),
                      rp_note("Hollow red markers are days with a stockout: they are not scored, because recorded sales understate demand on those days."))),
        card("Checking the demand estimate", "Hide known sales hours, estimate them, compare with the truth",
             bslib::layout_columns(col_widths = bslib::breakpoints(sm = 12, lg = c(5, 7)),
               htmltools::div(reactable::reactableOutput(ns("lat_tbl")), shiny::uiOutput(ns("lat_note"))),
               plotly::plotlyOutput(ns("lat_cut"), height = "260px")))),
      bslib::nav_panel("Stockout risk", value = "risk",
        two(card("How well does the model predict tomorrow's stockouts?", NULL, reactable::reactableOutput(ns("risk_tbl")), shiny::uiOutput(ns("risk_note"))),
            card("Right and wrong predictions (held-out week)", NULL, shiny::uiOutput(ns("confusion")))),
        card("What raises the chance of a stockout?", "Odds ratio > 1 = higher chance; lines are 95% confidence intervals", plotly::plotlyOutput(ns("coefs"), height = "280px"))),
      bslib::nav_panel("CSV Downloads", value = "downloads", shiny::uiOutput(ns("downloads"))),
      bslib::nav_panel("Advanced details", value = "adv",
        htmltools::p(class = "rp-sub", "Technical material for the assessment. These charts need some statistics background."),
        bslib::accordion(id = ns("adv"), open = "heat", multiple = TRUE, class = "rp-accordion",
          bslib::accordion_panel("Unusual sales days (anomaly heatmap)", value = "heat",
            plotly::plotlyOutput(ns("heat"), height = "640px"), shiny::uiOutput(ns("heat_note")),
            htmltools::h6(class = "rp-mini-h", "How the |z| threshold changes the number of flags"), plotly::plotlyOutput(ns("thr"), height = "240px")),
          bslib::accordion_panel("Decision rules behind the suggestions", value = "rules", shiny::uiOutput(ns("rules"))),
          bslib::accordion_panel("Demand-estimate validation: every test day", value = "latsc", plotly::plotlyOutput(ns("lat_sc"), height = "320px")),
          bslib::accordion_panel("Are the risk probabilities well calibrated?", value = "calib", plotly::plotlyOutput(ns("calib"), height = "280px")),
          bslib::accordion_panel("Promotions (association, not cause)", value = "promo", reactable::reactableOutput(ns("promo"))),
          bslib::accordion_panel("Hourly replay check of the alerts", value = "replay", shiny::uiOutput(ns("replay"))),
          bslib::accordion_panel("Dataset and limitations", value = "limits", shiny::uiOutput(ns("dataset"))))))
  )
}

mod_results_server <- function(id, RP, state, recs_r, anoms_r) {
  shiny::moduleServer(id, function(input, output, session) {
    q <- RP$quality; m <- RP$manifest; sid <- m$store_id
    rt <- function(df, ...) reactable::reactable(df, compact = TRUE, sortable = FALSE, ...)
    adv_open <- function(p) shiny::reactive(p %in% (input$adv %||% character()))

    # ---- data preparation ----
    output$dq_kpis <- shiny::renderUI({
      mb <- unlist(q$raw_profile$missing_by_column)
      imputed <- sum(unlist(q[c("imputed_precpt", "imputed_avg_temperature", "imputed_avg_humidity", "imputed_avg_wind_level")]), na.rm = TRUE)
      issues <- sum(unlist(q[c("duplicates_removed", "hourly_wrong_length", "hourly_daily_mismatch", "negative_sales_rows", "discount_out_of_range", "stock_count_mismatch")]), na.rm = TRUE)
      htmltools::div(class = "rp-kpis",
        rp_kpi("Raw rows", fmt_num(q$raw_profile$rows, 0), sprintf("%s columns · %s products", q$raw_profile$columns, q$raw_profile$products), "database"),
        rp_kpi("Cleaned rows", fmt_num(q$rows_clean, 0), sprintf("%s to %s", q$date_min, q$date_max), "broom"),
        rp_kpi("Duplicates removed", q$duplicates_removed %||% 0, "duplicate product-days", "clone", if ((q$duplicates_removed %||% 0) > 0) "warning" else "good"),
        rp_kpi("Rows fixed by checks", fmt_num(issues, 0), "length, sum, sign, discount and stock-count checks", "list-check", if (issues > 0) "warning" else "good"),
        rp_kpi("Missing values", fmt_num(sum(mb, na.rm = TRUE), 0), sprintf("%s weather values filled with the store median", fmt_num(imputed, 0)), "circle-half-stroke",
               if (sum(mb, na.rm = TRUE) > 0) "warning" else "good"))
    }) |> shiny::bindCache(sid, "dq_kpis")
    output$dims <- reactable::renderReactable(rt(data.frame(
      Item = c("Rows (product-days)", "Columns", "Products", "Date range", "Training / evaluation rows"),
      Raw = c(fmt_num(q$raw_profile$rows, 0), q$raw_profile$columns, q$raw_profile$products, paste(q$raw_profile$date_min, "to", q$raw_profile$date_max),
              paste(q$raw_profile$rows_by_split$train, "/", q$raw_profile$rows_by_split$eval)),
      Cleaned = c(fmt_num(q$rows_clean, 0), "Daily table + 24-hour matrices", q$products, paste(q$date_min, "to", q$date_max),
                  paste(sum(RP$daily$split == "train"), "/", sum(RP$daily$split == "eval")))))) |> shiny::bindCache(sid, "dims")
    output$issues <- reactable::renderReactable(rt(data.frame(
      Check = c("Duplicate product-days", "Hourly lists not of length 24", "Hourly sum ≠ daily total (> 0.05)", "Negative sales values",
                "Discount outside (0, 1]", "Out-of-stock hour count ≠ recount from hourly flags", "Missing product-days in the calendar"),
      Found = c(q$duplicates_removed, q$hourly_wrong_length, q$hourly_daily_mismatch, q$negative_sales_rows, q$discount_out_of_range, q$stock_count_mismatch, q$missing_product_days),
      Treatment = c("Kept first occurrence", "Row removed", "Daily total replaced by the hourly sum", "Set to 0", "Set to 1.0 (no discount)",
                    "Recomputed from hourly flags (06:00–21:59)", "Reported; series kept as observed")))) |> shiny::bindCache(sid, "issues")
    output$missing <- reactable::renderReactable({
      mb <- q$raw_profile$missing_by_column
      imp <- c(precpt = q$imputed_precpt, avg_temperature = q$imputed_avg_temperature, avg_humidity = q$imputed_avg_humidity, avg_wind_level = q$imputed_avg_wind_level)
      after <- vapply(names(mb), function(n) if (n %in% names(imp)) 0L else as.integer(mb[[n]]), 0L)
      rt(data.frame(row.names = NULL, Column = names(mb), Before = unname(unlist(mb)), After = unname(after),
                    Treatment = ifelse(names(mb) %in% names(imp) & unlist(mb) > 0, "Filled with store median", ifelse(unlist(mb) > 0, "Row-level check", "None needed"))),
         defaultPageSize = 8)
    }) |> shiny::bindCache(sid, "missing")
    output$before_after <- plotly::renderPlotly({
      x <- RP$daily[RP$daily$any_stockout == 1, ]
      if (!nrow(x)) return(rp_empty_plot("No stockout days"))
      plotly::plot_ly() |>
        plotly::add_histogram(x = x$sale_amount, name = "Recorded sales", marker = list(color = RP_COL$recorded, opacity = 0.55), nbinsx = 40) |>
        plotly::add_histogram(x = x$latent, name = "Estimated demand", marker = list(color = RP_COL$demand, opacity = 0.55), nbinsx = 40) |>
        rp_plotly_layout(xtitle = "Daily total (normalised units)", ytitle = "Product-days", hovermode = "closest") |>
        plotly::layout(barmode = "overlay")
    }) |> shiny::bindCache(sid, "before_after")
    output$ba_note <- shiny::renderUI({
      x <- RP$daily[RP$daily$any_stockout == 1, ]; shiny::req(nrow(x))
      rp_note(sprintf("On the %d product-days with a stockout, the typical (median) daily total rises from %s recorded to %s estimated. %d days used the hourly-profile method and %d a fallback average (less than %.0f%% of the day in stock).",
                      nrow(x), fmt_num(stats::median(x$sale_amount), 2), fmt_num(stats::median(x$latent), 2),
                      sum(x$latent_method == "profile"), sum(x$latent_method == "fallback"), 100 * m$thresholds$min_share_in))
    }) |> shiny::bindCache(sid, "ba_note")
    output$features <- reactable::renderReactable(rt(as.data.frame(RP$feature_dictionary), columns = list(
      feature = reactable::colDef(name = "Feature", width = 170), definition = reactable::colDef(name = "Definition"),
      uses_future = reactable::colDef(name = "Uses future data?", width = 190)))) |> shiny::bindCache(sid, "features")

    # ---- exploration ----
    output$store_wdh <- plotly::renderPlotly(ch_weekday_hour(RP$store_weekday_hour)) |> shiny::bindCache(sid, "store_wdh")
    output$wdh_note <- shiny::renderUI({
      w <- RP$store_weekday_hour; by_h <- stats::aggregate(mean_sales ~ hour, w, mean); top <- by_h$hour[order(-by_h$mean_sales)][1:2]
      rp_note(sprintf("The busiest hours are %02d:00 and %02d:00. Sales are close to zero overnight (00–05).", top[1], top[2]))
    }) |> shiny::bindCache(sid, "wdh_note")
    output$inout <- plotly::renderPlotly(ch_instock_vs_out(RP$instock_vs_out)) |> shiny::bindCache(sid, "inout")
    output$inout_note <- shiny::renderUI({
      x <- RP$instock_vs_out
      a <- stats::weighted.mean(x$mean_sales[x$status == "In stock"], x$hours[x$status == "In stock"])
      b <- stats::weighted.mean(x$mean_sales[x$status == "Out of stock"], x$hours[x$status == "Out of stock"])
      rp_note(sprintf("%s per hour in stock vs %s out of stock: sales during stockouts are almost entirely missing, so recorded sales cannot be used as demand.", fmt_num(a, 3), fmt_num(b, 3)))
    }) |> shiny::bindCache(sid, "inout_note")
    output$cats <- plotly::renderPlotly({
      x <- RP$daily
      cp <- stats::aggregate(cbind(observed = sale_amount, latent = latent, stock_h = stock_h) ~ first_category_id, x, sum)
      cp$products <- as.integer(table(RP$products$first_category_id)[as.character(cp$first_category_id)])
      cp$n <- as.integer(table(x$first_category_id)[as.character(cp$first_category_id)])
      cp$so_rate <- cp$stock_h / (16 * cp$n); cp$unmet_share <- (cp$latent - cp$observed) / pmax(cp$latent, 1e-9)
      cp$category <- paste("Category", cp$first_category_id)
      ch_categories(utils::head(cp[order(-cp$latent), ], 12))
    }) |> shiny::bindCache(sid, "cats")
    output$variab <- plotly::renderPlotly(ch_variability(RP$variability)) |> shiny::bindCache(sid, "variab")
    output$var_note <- shiny::renderUI({
      v <- RP$variability
      rp_note(sprintf("Typical day-to-day variability (median CV) is %s. %d products lose more than 10%% of their demand to stockouts.", fmt_num(stats::median(v$cv), 2), sum(v$unmet_share > 0.10)))
    }) |> shiny::bindCache(sid, "var_note")

    # ---- forecasting ----
    output$fc_method <- shiny::renderUI({
      htmltools::div(class = "rp-rules",
        htmltools::tags$ol(
          htmltools::tags$li(htmltools::strong("Estimate demand first. "), "On stockout days, recorded sales are too low. The hours that were out of stock are filled in using the product's usual hourly sales pattern (fitted on fully in-stock training days)."),
          htmltools::tags$li(htmltools::strong("Two models per product. "), "A simple baseline (same weekday last week, ‘seasonal naive’) and ETS exponential smoothing (R package fable), both on estimated demand."),
          htmltools::tags$li(htmltools::strong("Fair testing. "), sprintf("Rolling-origin cross-validation inside the training period (4 starting points: %s, 7 days ahead each). The model was chosen on this only: %s.",
                                                                       paste(m$cv_origins, collapse = ", "), toupper(m$chosen_model))),
          htmltools::tags$li(htmltools::strong("Final check. "), sprintf("Both models were then scored once on the untouched evaluation week (%s to %s).", m$eval_range[1], m$eval_range[2])),
          htmltools::tags$li(htmltools::strong("Scoring. "), "Only in-stock days are scored, because on stockout days recorded sales are not true demand. Measures: MAE and RMSE (average error in units), WAPE (error as a share of sales), bias (over- or under-forecasting) and 80% interval coverage.")))
    }) |> shiny::bindCache(sid, "fc_method")
    output$fc_tbl <- reactable::renderReactable({
      cv <- RP$forecast_cv_overall; ev <- RP$forecast_eval_overall
      x <- rbind(cbind(Window = "Cross-validation (training)", cv), cbind(Window = "Held-out week", ev))
      rt(data.frame(Window = x$Window, Model = ifelse(x$.model == "ets", "ETS", "Seasonal naive"), Days = x$n_instock,
                    MAE = fmt_num(x$MAE, 3), RMSE = fmt_num(x$RMSE, 3), WAPE = fmt_pct(x$WAPE, 1), Bias = fmt_pct(x$bias, 1),
                    `80% coverage` = fmt_pct(x$coverage80, 0), check.names = FALSE))
    }) |> shiny::bindCache(sid, "fc_tbl")
    output$fc_note <- shiny::renderUI({
      ev <- RP$forecast_eval_overall; e1 <- ev$WAPE[ev$.model == "ets"]; e2 <- ev$WAPE[ev$.model == "snaive"]; b1 <- ev$bias[ev$.model == "ets"]
      rp_note(sprintf("On the held-out week ETS %s the simple baseline (error %s vs %s). It over-forecasts (bias %s), partly because the days that sell out — the busiest ones — are left out of scoring. Error is high for slow-selling products with many zero-sale days, so the app shows a reliability label per product.",
                      if (e1 < e2) "beats" else "does not beat", fmt_pct(e1, 1), fmt_pct(e2, 1), fmt_pct(b1, 0)))
    }) |> shiny::bindCache(sid, "fc_note")
    output$fc_bars <- plotly::renderPlotly(ch_model_bars(RP$forecast_cv_overall, RP$forecast_eval_overall)) |> shiny::bindCache(sid, "fc_bars")
    shiny::observeEvent(state$product, shiny::updateSelectizeInput(session, "fc_prod", selected = state$product), ignoreNULL = TRUE)
    output$fc_avf <- plotly::renderPlotly({ shiny::req(input$fc_prod); ch_actual_vs_fc(RP$forecast_eval[RP$forecast_eval$product_id == as.integer(input$fc_prod), ]) }) |>
      shiny::bindCache(sid, input$fc_prod, "fc_avf")
    output$lat_tbl <- reactable::renderReactable({
      x <- as.data.frame(RP$latent_val$metrics)
      x$method <- c(profile_method = "Hourly-pattern estimate", observed_only = "Recorded sales only")[x$method]
      rt(data.frame(Method = x$method, MAE = fmt_num(x$MAE, 3), WAPE = fmt_pct(x$WAPE, 1), Bias = fmt_pct(x$bias, 1)))
    }) |> shiny::bindCache(sid, "lat_tbl")
    output$lat_note <- shiny::renderUI(rp_note(sprintf("On %d fully in-stock days, the hours after a random cut-off (12:00–20:00) were hidden as if sold out, then estimated. The estimate's error is much smaller than simply using recorded sales.", RP$latent_val$n))) |> shiny::bindCache(sid, "lat_note")
    output$lat_cut <- plotly::renderPlotly(ch_latent_cutoff(RP$latent_validation_by_cutoff)) |> shiny::bindCache(sid, "lat_cut")

    # ---- stockout risk ----
    output$risk_tbl <- reactable::renderReactable({
      x <- as.data.frame(RP$risk_metrics)
      x$set <- c(logistic_validation = "Model · validation (threshold chosen here)", logistic_test = "Model · held-out week", frequency_baseline_test = "Simple baseline · held-out week")[x$set]
      rt(data.frame(Set = x$set, n = x$n, `Stockout rate` = fmt_pct(x$base_rate, 1), AUC = fmt_num(x$AUC, 3),
                    Precision = fmt_pct(x$precision, 0), Recall = fmt_pct(x$recall, 0), F1 = fmt_num(x$F1, 3), check.names = FALSE))
    }) |> shiny::bindCache(sid, "risk_tbl")
    output$risk_note <- shiny::renderUI({
      t <- RP$risk_metrics[RP$risk_metrics$set == "logistic_test", ]; b <- RP$risk_metrics[RP$risk_metrics$set == "frequency_baseline_test", ]
      rp_note(sprintf("Target: a product out of stock for 4+ of the 16 opening hours tomorrow. Logistic regression using only information up to yesterday; split by date (fit %s–%s, validation %s–%s, test %s–%s). ",
                      m$risk_windows$fit[1], m$risk_windows$fit[2], m$risk_windows$validation[1], m$risk_windows$validation[2], m$risk_windows$test[1], m$risk_windows$test[2]),
              sprintf("AUC %s vs %s for the simple baseline: better than guessing from history, but a ranking aid, not a precise prediction. Precision %s means about %s in 10 flagged products really ran out.",
                      fmt_num(t$AUC, 2), fmt_num(b$AUC, 2), fmt_pct(t$precision, 0), round(10 * t$precision)))
    }) |> shiny::bindCache(sid, "risk_note")
    output$confusion <- shiny::renderUI({
      x <- RP$risk_metrics[RP$risk_metrics$set == "logistic_test", ]; shiny::req(nrow(x))
      cell <- function(v, lab, cls) htmltools::div(class = paste("rp-cm", cls), htmltools::strong(v), htmltools::span(lab))
      htmltools::div(class = "rp-cm-grid",
        htmltools::div(), htmltools::div(class = "rp-cm-h", "Predicted: stockout"), htmltools::div(class = "rp-cm-h", "Predicted: no stockout"),
        htmltools::div(class = "rp-cm-h", "Actually ran out"), cell(x$TP, "caught", "ok"), cell(x$FN, "missed", "bad"),
        htmltools::div(class = "rp-cm-h", "Did not run out"), cell(x$FP, "false alarm", "bad"), cell(x$TN, "correctly calm", "ok"))
    }) |> shiny::bindCache(sid, "confusion")
    output$coefs <- plotly::renderPlotly(ch_coefs(RP$risk_coefficients)) |> shiny::bindCache(sid, "coefs")

    # ---- CSV downloads ----
    output$downloads <- shiny::renderUI({
      item <- function(id, label, text) htmltools::div(class = "rp-csv-item",
        htmltools::div(class = "rp-csv-text", htmltools::strong(label), htmltools::span(text)),
        shiny::downloadButton(session$ns(id), "Download CSV", class = "btn-outline-secondary btn-sm"))
      bslib::card(
        bslib::card_header(rp_card_title("Download analytical results", sprintf("Store %s · %s to %s", sid, m$date_min, m$date_max), "download")),
        htmltools::p(class = "rp-csv-intro", "These CSV files contain the project's analytical outputs for this store, as shown in the app. They open in Excel, Google Sheets or R. Sales are in normalised units, as in the source data."),
        htmltools::div(class = "rp-csv-grid",
          item("dl_recs", "Suggested actions", "Every rule-based suggestion with its reason, evidence, urgency and priority."),
          item("dl_risk", "Product risk table", "Each product's chance of a stockout tomorrow, missed demand and top suggestion."),
          item("dl_metrics", "Model evaluation", "Forecast, stockout-risk and demand-estimate accuracy scores."),
          item("dl_anoms", "Unusual days", "Days with unusually high or low sales and their likely cause."),
          item("dl_alerts", "Replay alerts", "Alerts from the hour-by-hour historical replay of the evaluation week.")))
    }) |> shiny::bindCache(sid, "downloads")
    fname <- function(x, ext = "csv") sprintf("retailpulse_store%s_%s.%s", sid, x, ext)
    w_csv <- function(df, file) utils::write.csv(df, file, row.names = FALSE, na = "")
    output$dl_recs <- shiny::downloadHandler(filename = function() fname("suggested_actions"), content = function(file) {
      r <- recs_r(); w_csv(data.frame(product = plabel(r$product_id), action = r$action, urgency = r$urgency, reliability = r$reliability, priority = r$priority,
                                      reason = r$reason, evidence = r$evidence, if_ignored = r$if_ignored, rule = r$rule), file) })
    output$dl_risk <- shiny::downloadHandler(filename = function() fname("product_risk"), content = function(file) {
      p <- RP$products; r <- recs_r(); top <- r[!duplicated(r$product_id), c("product_id", "action", "urgency", "reliability")]
      out <- merge(p[, c("product_id", "label", "category", "mean_latent", "unmet_share", "stockout_hour_rate", "sellout_share", "median_sellout_hour", "risk")], top, by = "product_id", all.x = TRUE)
      names(out)[names(out) == "risk"] <- "stockout_chance_tomorrow"; w_csv(out[order(-out$stockout_chance_tomorrow), ], file) })
    output$dl_metrics <- shiny::downloadHandler(filename = function() fname("model_evaluation"), content = function(file) {
      cv <- RP$forecast_cv_overall; ev <- RP$forecast_eval_overall
      fc <- rbind(cbind(window = "rolling-origin CV", as.data.frame(cv)), cbind(window = "held-out week", as.data.frame(ev)))
      fc <- data.frame(task = "forecast", window = fc$window, model = fc$.model, n = fc$n_instock, MAE = fc$MAE, RMSE = fc$RMSE, WAPE = fc$WAPE, bias = fc$bias, coverage80 = fc$coverage80, AUC = NA, F1 = NA, precision = NA, recall = NA)
      rk <- as.data.frame(RP$risk_metrics)
      rk <- data.frame(task = "stockout risk", window = rk$set, model = ifelse(grepl("baseline", rk$set), "frequency baseline", "logistic"), n = rk$n,
                       MAE = NA, RMSE = NA, WAPE = NA, bias = NA, coverage80 = NA, AUC = rk$AUC, F1 = rk$F1, precision = rk$precision, recall = rk$recall)
      lv <- as.data.frame(RP$latent_val$metrics)
      lt <- data.frame(task = "demand estimate validation", window = "hidden-hours test", model = lv$method, n = RP$latent_val$n,
                       MAE = lv$MAE, RMSE = NA, WAPE = lv$WAPE, bias = lv$bias, coverage80 = NA, AUC = NA, F1 = NA, precision = NA, recall = NA)
      w_csv(rbind(lt, fc, rk), file) })
    output$dl_anoms <- shiny::downloadHandler(filename = function() fname("unusual_days"), content = function(file) {
      a <- anoms_r(); w_csv(data.frame(date = a$dt, product = plabel(a$product_id), direction = a$direction, cause = a$cause, z = a$z, observed = a$observed, expected = a$expected), file) })
    output$dl_alerts <- shiny::downloadHandler(filename = function() fname("replay_alerts"), content = function(file) {
      a <- RP$alerts; w_csv(data.frame(timestamp = format(a$ts, "%Y-%m-%d %H:00"), product = plabel(a$product_id), severity = a$severity, type = a$type,
                                       observed = a$observed, expected = a$expected, message = a$message, note = "Historical replay of the evaluation week, not live data"), file) })

    # ---- advanced details (each panel renders only when opened) ----
    open_heat <- adv_open("heat"); open_latsc <- adv_open("latsc"); open_cal <- adv_open("calib")
    output$heat <- plotly::renderPlotly({
      shiny::req(open_heat())
      d <- RP$daily; last <- max(d$dt); w <- d[d$dt > last - 42, ]
      score <- tapply(pmax(abs(w$z), 0, na.rm = TRUE) * (abs(w$z) >= state$zthr), w$product_id, sum, na.rm = TRUE)
      keep <- as.integer(names(sort(score, decreasing = TRUE)))[seq_len(min(40, length(score)))]
      ch_heatmap(d[d$product_id %in% keep, ], RP$label_of, days = 42, source = session$ns("heat"))
    })
    output$heat_note <- shiny::renderUI({
      shiny::req(open_heat())
      a <- anoms_r(); a <- a[a$dt > max(RP$daily$dt) - 42, ]
      rp_note(sprintf("40 products with the most unusual days in the last 6 weeks. Each cell compares that day's sales with the product's own normal level for that weekday (robust z-score). Green = below normal, gold = above; × = 4+ hours out of stock. %d days are flagged at |z| ≥ %.1f: %d have a recorded explanation (stockout, promotion, holiday or rain), %d do not.",
                      nrow(a), state$zthr, sum(a$cause != "Unexplained"), sum(a$cause == "Unexplained")))
    })
    output$thr <- plotly::renderPlotly({
      shiny::req(open_heat())
      z <- RP$daily$z[!is.na(RP$daily$z)]; grid <- seq(2, 5, by = 0.25)
      x <- data.frame(t = grid, n = vapply(grid, function(t) sum(abs(z) >= t), 0))
      plotly::plot_ly(x, x = ~t, y = ~n, type = "scatter", mode = "lines+markers", line = list(color = RP_COL$forest2), marker = list(color = RP_COL$forest2),
                      hovertemplate = "|z| ≥ %{x}: %{y} flags<extra></extra>") |>
        rp_plotly_layout(xtitle = "Threshold |z|", ytitle = "Flagged days", legend = FALSE) |>
        plotly::layout(shapes = list(list(type = "line", x0 = state$zthr, x1 = state$zthr, yref = "paper", y0 = 0, y1 = 1, line = list(color = RP_COL$gold_dk, width = 1.5, dash = "dot"))))
    })
    output$rules <- shiny::renderUI({
      r <- m$rules
      htmltools::div(class = "rp-rules",
        htmltools::p(sprintf("Unusual days: robust z-score of recorded sales against the product's weekday-adjusted median of the previous %d in-stock days. Flagged when |z| ≥ %.1f. There is no ground truth, so detection accuracy is not claimed.",
                             m$thresholds$baseline_window, state$zthr)),
        htmltools::tags$ul(
          htmltools::tags$li(sprintf("R1 Consider replenishing earlier: %g+ of the last 7 days with 4+ hours out of stock, or tomorrow's stockout chance ≥ %.0f%% and missed demand ≥ %.0f%%.", r$stockout_days_thr, 100 * m$risk_threshold, 100 * r$lost_share_thr)),
          htmltools::tags$li("R2 Investigate unexplained sales drop: an unexplained low-sales day in the last 7 days."),
          htmltools::tags$li(sprintf("R3 Review possible demand surge: next-7-day forecast ≥ %.0f%% of the last 7 days, or an unexplained high-sales day.", 100 * r$surge_ratio)),
          htmltools::tags$li(sprintf("R4 Plan for lower demand: next-7-day forecast ≤ %.0f%% of the last 7 days (reliable forecasts only).", 100 * r$decline_ratio)),
          htmltools::tags$li(sprintf("R5 Use caution: forecast unreliable (past error > %.0f%%, fewer than %g fully in-stock days, or mostly zero-sale days).", 100 * r$wape_low_reliability, r$min_instock_days)),
          htmltools::tags$li("R6 Maintain current approach: no other rule applies.")),
        htmltools::p("Priority = urgency (High 3, Medium 2, Low 1, Info 0.5) × (1 + missed-demand share + stockout chance + recent unusual activity). These thresholds are documented design choices, not proven boundaries."))
    }) |> shiny::bindCache(sid, "rules")
    output$lat_sc <- plotly::renderPlotly({ shiny::req(open_latsc()); ch_latent_scatter(RP$latent_validation_rows) })
    output$calib <- plotly::renderPlotly({ shiny::req(open_cal()); ch_calibration(RP$risk_calibration) })
    output$promo <- reactable::renderReactable({
      p <- RP$promo_effects
      rt(data.frame(Category = paste("Category", p$first_category_id), `Promotion days` = p$n_promo_days,
                    `Demand at 10% off` = ifelse(is.na(p$lift_10pp), "too few days", sprintf("× %.2f (95%% CI %.2f–%.2f)", p$lift_10pp, p$lift_10pp_lo, p$lift_10pp_hi)),
                    check.names = FALSE), defaultPageSize = 8)
    }) |> shiny::bindCache(sid, "promo")
    output$replay <- shiny::renderUI({
      a <- RP$alerts
      rp_note(sprintf("To check that alerts would work day to day, the evaluation week was replayed hour by hour using only information available at each hour (forecasts made before the week). This raised %d alerts: %d critical (out of stock in a peak hour), %d warnings (sales outside the expected range for 3+ hours) and %d informational. This is a historical replay, not a live feed. The full list is in the Replay alerts download.",
                      nrow(a), sum(a$severity == "Critical"), sum(a$severity == "Warning"), sum(a$severity == "Info")))
    }) |> shiny::bindCache(sid, "replay")
    output$dataset <- shiny::renderUI({
      htmltools::div(class = "rp-rules",
        htmltools::tags$dl(class = "rp-dl",
          htmltools::tags$dt("Source"), htmltools::tags$dd(htmltools::a(href = "https://huggingface.co/datasets/Dingdong-Inc/FreshRetailNet-50K", target = "_blank", "FreshRetailNet-50K (Dingdong-Inc)"), " · Wang et al. (2025), arXiv:2505.16319 · CC BY 4.0"),
          htmltools::tags$dt("Data used"), htmltools::tags$dd(m$mode_note),
          htmltools::tags$dt("Store"), htmltools::tags$dd(sprintf("Store %s · %d products · training %s to %s · evaluation %s to %s", m$store_id, m$products, m$train_range[1], m$train_range[2], m$eval_range[1], m$eval_range[2])),
          htmltools::tags$dt("Results generated"), htmltools::tags$dd(sprintf("%s (pipeline runtime %.0f s, %s)", m$generated_at, m$runtime_seconds, m$r_version))),
        htmltools::tags$ul(
          htmltools::tags$li("Sales are normalised by an undisclosed factor: every value is in normalised units, not money, kilograms or item counts."),
          htmltools::tags$li("There is no stock-on-hand, price, cost, lead-time or shelf-life data, so no order quantities, dates or money losses are produced."),
          htmltools::tags$li("Only opening hours (06:00–21:59) are used for stockouts; overnight 'out of stock' flags may just mean closed."),
          htmltools::tags$li("Estimated demand assumes a stable hourly sales pattern; its error is measured and it is always labelled as an estimate."),
          htmltools::tags$li("90 training days: weekly patterns only, no yearly seasonality. Forecasts beyond 7 days were not tested."),
          htmltools::tags$li("The stores belong to one large operator, so they are a stand-in for a small independent shop."),
          htmltools::tags$li("Promotion figures are associations, not causal effects.")))
    }) |> shiny::bindCache(sid, "dataset")
  })
}
