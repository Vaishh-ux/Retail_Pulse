# Page 6 - Report and downloads --------------------------------------------------------------
# The full R Markdown report (report/report.Rmd) is knitted from the same outputs at build
# time, one per shipped store. This page previews it and offers it plus the key tables
# as downloads. CSV downloads reflect the app's current anomaly threshold.

mod_report_ui <- function(id, RP, report_path = NULL) {
  ns <- shiny::NS(id)
  m <- RP$manifest
  sec <- function(icon, title, text) htmltools::div(class = "rp-report-sec", shiny::icon(icon), htmltools::div(htmltools::strong(title), htmltools::span(text)))
  htmltools::tagList(
    htmltools::div(class = "rp-hero",
      htmltools::div(htmltools::div(class = "rp-eyebrow", "Report"),
        htmltools::h1(sprintf("Store %s analysis report", m$store_id)),
        htmltools::p(sprintf("%s · %d products · %s to %s · results generated %s", m$mode_note, m$products, m$date_min, m$date_max, substr(m$generated_at %||% "", 1, 10))))),
    bslib::layout_columns(col_widths = bslib::breakpoints(sm = 12, lg = c(7, 5)),
      bslib::card(
        bslib::card_header(rp_card_title("What the report contains", "R Markdown · ggplot2 figures · inline-computed text · R code folded", "book-open")),
        htmltools::div(class = "rp-report-grid",
          sec("database", "Dataset and coverage", "Source, licence, store, date ranges, data-quality checks and cleaning"),
          sec("lightbulb", "Key business insights", "Unmet demand, stockout timing, weekday and hour patterns"),
          sec("triangle-exclamation", "Product-level risk", "Next-day stockout risk, products losing the most demand"),
          sec("chart-line", "Forecast results", "ETS vs seasonal naive, rolling-origin CV and held-out week"),
          sec("bullseye", "Evaluation metrics", "MAE, RMSE, WAPE, bias, coverage; AUC, F1, calibration"),
          sec("list-check", "Recommendations", "Rule-based actions with evidence and the rule that fired"),
          sec("circle-info", "Limitations", "Normalised units, no inventory or cost data, observational effects"))),
      bslib::card(
        bslib::card_header(rp_card_title("Download", "files reflect this store", "download")),
        if (!is.null(report_path)) htmltools::div(class = "rp-dl-row",
          htmltools::a(href = report_path, target = "_blank", class = "btn btn-primary btn-sm", shiny::icon("up-right-from-square"), " Open full report"),
          shiny::downloadButton(ns("dl_report"), "Download report (HTML)", class = "btn-gold btn-sm"))
        else htmltools::div(class = "rp-warn", "The HTML report has not been knitted for this store. Run rmarkdown::render('report/report.Rmd'). The tables below can still be downloaded."),
        htmltools::p(class = "rp-sub", "To save as PDF, open the full report and use your browser's Print → Save as PDF."),
        htmltools::h6(class = "rp-side-h", "Tables (CSV)"),
        htmltools::div(class = "rp-dl-row",
          shiny::downloadButton(ns("dl_recs"), "Recommendations", class = "btn-outline-secondary btn-sm"),
          shiny::downloadButton(ns("dl_risk"), "Product risk table", class = "btn-outline-secondary btn-sm"),
          shiny::downloadButton(ns("dl_alerts"), "Replay alerts", class = "btn-outline-secondary btn-sm"),
          shiny::downloadButton(ns("dl_anoms"), "Anomalies", class = "btn-outline-secondary btn-sm"),
          shiny::downloadButton(ns("dl_metrics"), "Evaluation metrics", class = "btn-outline-secondary btn-sm")),
        shiny::uiOutput(ns("summary")))),
    if (!is.null(report_path)) bslib::card(full_screen = TRUE,
      bslib::card_header(rp_card_title("Report preview", NULL, "eye")),
      htmltools::tags$iframe(src = report_path, class = "rp-report-frame", title = "RetailPulse report", loading = "lazy"))
  )
}

mod_report_server <- function(id, RP, state, recs_r, anoms_r) {
  shiny::moduleServer(id, function(input, output, session) {
    m <- RP$manifest
    sid <- m$store_id
    www <- file.path(rp_app_root(), "app", "www")
    fname <- function(x, ext = "csv") sprintf("retailpulse_store%s_%s.%s", sid, x, ext)
    w_csv <- function(df, file) utils::write.csv(df, file, row.names = FALSE, na = "")

    risk_table <- shiny::reactive({
      p <- RP$products; r <- recs_r(); top <- r[!duplicated(r$product_id), c("product_id", "action", "urgency", "reliability", "stockout_days7", "lost_share7", "fc_ratio")]
      out <- merge(p[, c("product_id", "label", "category", "mean_latent", "unmet_share", "stockout_hour_rate", "sellout_share", "median_sellout_hour", "risk")], top, by = "product_id", all.x = TRUE)
      names(out)[names(out) == "risk"] <- "next_day_stockout_risk"
      out[order(-out$next_day_stockout_risk), ]
    })

    output$summary <- shiny::renderUI({
      r <- recs_r(); d <- RP$daily
      rp_note(sprintf("Current data: %d products, %s product-days, estimated unmet demand %s, %d products with a High or Medium action, %d anomalies at |z| ≥ %.1f.",
                      m$products, fmt_num(nrow(d), 0), fmt_pct(sum(d$lost) / sum(d$latent), 1),
                      length(unique(r$product_id[r$urgency %in% c("High", "Medium")])), NROW(anoms_r()), state$zthr))
    })

    output$dl_report <- shiny::downloadHandler(filename = function() fname("report", "html"), content = function(file) {
      src <- file.path(www, "reports", sprintf("report_%s.html", sid))
      if (!file.exists(src)) src <- file.path(www, "report.html")
      file.copy(src, file)
    })
    output$dl_recs <- shiny::downloadHandler(filename = function() fname("recommendations"), content = function(file) {
      r <- recs_r()
      w_csv(data.frame(product = plabel(r$product_id), action = r$action, urgency = r$urgency, reliability = r$reliability,
                       priority = r$priority, reason = r$reason, evidence = r$evidence, if_ignored = r$if_ignored, rule = r$rule,
                       type = r$recommendation_type), file)
    })
    output$dl_risk <- shiny::downloadHandler(filename = function() fname("product_risk"), content = function(file) w_csv(risk_table(), file))
    output$dl_alerts <- shiny::downloadHandler(filename = function() fname("replay_alerts"), content = function(file) {
      a <- RP$alerts
      w_csv(data.frame(timestamp = format(a$ts, "%Y-%m-%d %H:00"), product = plabel(a$product_id), severity = a$severity, type = a$type,
                       observed = a$observed, expected = a$expected, message = a$message,
                       note = "Historical replay of the evaluation week, not live data"), file)
    })
    output$dl_anoms <- shiny::downloadHandler(filename = function() fname("anomalies"), content = function(file) {
      a <- anoms_r()
      w_csv(data.frame(date = a$dt, product = plabel(a$product_id), direction = a$direction, cause = a$cause, z = a$z,
                       observed = a$observed, expected = a$expected, threshold = state$zthr), file)
    })
    output$dl_metrics <- shiny::downloadHandler(filename = function() fname("evaluation_metrics"), content = function(file) {
      cv <- RP$forecast_cv_overall; ev <- RP$forecast_eval_overall
      fc <- rbind(cbind(window = "rolling-origin CV", as.data.frame(cv)), cbind(window = "held-out eval week", as.data.frame(ev)))
      fc <- data.frame(task = "forecast", window = fc$window, model = fc$.model, n = fc$n_instock, MAE = fc$MAE, RMSE = fc$RMSE, WAPE = fc$WAPE,
                       bias = fc$bias, coverage80 = fc$coverage80, AUC = NA, F1 = NA, precision = NA, recall = NA)
      rk <- as.data.frame(RP$risk_metrics)
      rk <- data.frame(task = "stockout risk", window = rk$set, model = ifelse(grepl("baseline", rk$set), "frequency baseline", "logistic"), n = rk$n,
                       MAE = NA, RMSE = NA, WAPE = NA, bias = NA, coverage80 = NA, AUC = rk$AUC, F1 = rk$F1, precision = rk$precision, recall = rk$recall)
      lv <- as.data.frame(RP$latent_val$metrics)
      lt <- data.frame(task = "latent demand validation", window = "hidden-hours test", model = lv$method, n = RP$latent_val$n,
                       MAE = lv$MAE, RMSE = NA, WAPE = lv$WAPE, bias = lv$bias, coverage80 = NA, AUC = NA, F1 = NA, precision = NA, recall = NA)
      w_csv(rbind(lt, fc, rk), file)
    })
  })
}
