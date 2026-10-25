# Page 4 - Forecasts and scenario analysis -------------------------------------------------------
# Everything on this page except the baseline forecast is HYPOTHETICAL.

mod_scenario_ui <- function(id, choices) {
  ns <- shiny::NS(id)
  bslib::layout_sidebar(
    sidebar = bslib::sidebar(width = 300, open = list(desktop = "open", mobile = "closed"),
      shiny::selectizeInput(ns("product"), "Product", choices = choices),
      shiny::sliderInput(ns("horizon"), "Forecast horizon (days)", 1, 14, 7, 1),
      htmltools::h6(class = "rp-side-h", "Hypothetical assumptions"),
      shiny::sliderInput(ns("growth"), "Demand change vs model forecast", min = -30, max = 50, value = 0, step = 5, post = "%"),
      shiny::sliderInput(ns("depth"), "Planned promotion depth", min = 0, max = 50, value = 0, step = 5, post = "% off"),
      htmltools::h6(class = "rp-side-h", "Detection and prioritisation settings"),
      shiny::sliderInput(ns("zthr"), "Anomaly threshold |z|", min = 2, max = 5, value = 3, step = 0.5),
      shiny::sliderInput(ns("w_lost"), "Weight: unmet demand", 0, 3, 1, 0.5),
      shiny::sliderInput(ns("w_risk"), "Weight: stockout risk", 0, 3, 1, 0.5),
      shiny::sliderInput(ns("w_anom"), "Weight: unusual activity", 0, 3, 1, 0.5),
      shiny::actionButton(ns("reset"), "Reset to defaults", class = "btn-outline-secondary btn-sm w-100")),
    htmltools::div(class = "rp-scenario-banner", shiny::icon("flask"), htmltools::div(htmltools::strong("Hypothetical scenario. "),
      "Assumption sliders change only this page. They do not predict what will happen; the promotion effect is an observational association, not a causal estimate. ",
      "The anomaly threshold and the horizon are shared with the other pages.")),
    bslib::card(
      bslib::card_header(rp_card_title("Scenario comparison", "Baseline (model, observed data) → hypothetical scenario", "code-compare")),
      shiny::uiOutput(ns("compare"))),
    bslib::card(full_screen = TRUE,
      bslib::card_header(shiny::uiOutput(ns("fc_title"), inline = TRUE)),
      plotly::plotlyOutput(ns("fc_plot"), height = "360px"),
      shiny::uiOutput(ns("fc_note"))),
    bslib::layout_columns(col_widths = bslib::breakpoints(sm = 12, lg = c(6, 6)),
      bslib::card(bslib::card_header(htmltools::div(class = "rp-card-title", "How does the threshold change what gets flagged?",
                                                    htmltools::span(class = "rp-sub", "Number of anomaly flags (whole period) at each |z| threshold"))),
                  plotly::plotlyOutput(ns("thr_plot"), height = "260px"), shiny::uiOutput(ns("thr_note"))),
      bslib::card(bslib::card_header(htmltools::div(class = "rp-card-title", "How do the weights change the priority order?",
                                                    htmltools::span(class = "rp-sub", "Top 12 products under your weights vs the default weights"))),
                  reactable::reactableOutput(ns("rank_tbl")), shiny::uiOutput(ns("rank_note"))))
  )
}

mod_scenario_server <- function(id, RP, state, build_recs) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns
    shiny::observeEvent(state$product, shiny::updateSelectizeInput(session, "product", selected = state$product), ignoreNULL = TRUE)
    shiny::observeEvent(input$product, if (nzchar(input$product)) state$product <- as.integer(input$product), ignoreInit = TRUE)
    shiny::observeEvent(state$horizon, if (!identical(state$horizon, input$horizon)) shiny::updateSliderInput(session, "horizon", value = state$horizon))
    shiny::observeEvent(input$horizon, state$horizon <- input$horizon, ignoreInit = TRUE)
    shiny::observeEvent(input$zthr, state$zthr <- input$zthr, ignoreInit = TRUE)
    shiny::observeEvent(input$reset, {
      for (n in c("growth", "depth")) shiny::updateSliderInput(session, n, value = 0)
      shiny::updateSliderInput(session, "zthr", value = RP$manifest$thresholds$anomaly_z)
      for (n in c("w_lost", "w_risk", "w_anom")) shiny::updateSliderInput(session, n, value = 1)
    })

    pid <- shiny::reactive({ shiny::req(input$product); as.integer(input$product) })
    growth_d <- shiny::debounce(shiny::reactive(input$growth), 400)
    base_recs <- shiny::reactive(build_recs(list(), state$zthr))
    scen_recs <- shiny::reactive({
      g <- 1 + growth_d() / 100
      if (abs(g - 1) < 1e-9) base_recs() else build_recs(list(), state$zthr, growth = g)
    })
    effect <- shiny::reactive({
      cat <- RP$products$first_category_id[RP$products$product_id == pid()]
      RP$promo_effects[RP$promo_effects$first_category_id == cat, ]
    })
    multiplier <- shiny::reactive({
      g <- 1 + input$growth / 100
      e <- effect(); depth <- input$depth / 100
      pm <- if (depth > 0 && nrow(e) && !is.na(e$beta)) rp_promo_multiplier(e$beta, e$se, depth) else c(mid = 1, lo = 1, hi = 1)
      list(growth = g, promo = pm, total = g * pm[["mid"]], usable = !(depth > 0 && (!nrow(e) || is.na(e$beta))))
    })

    output$fc_title <- shiny::renderUI(htmltools::div(class = "rp-card-title",
      sprintf("What demand can be expected for %s?", plabel(pid())),
      htmltools::span(class = "rp-sub", sprintf("Estimated demand, last 28 days · %s forecast for %d days · scenario in gold",
                                                toupper(RP$manifest$chosen_model), input$horizon))))
    output$fc_plot <- plotly::renderPlotly({
      h <- RP$daily[RP$daily$product_id == pid(), ]; h <- h[h$dt > max(h$dt) - 28, ]
      f <- RP$forecast_next[RP$forecast_next$product_id == pid() & RP$forecast_next$.model == RP$manifest$chosen_model, ]
      f <- f[order(f$dt), ][seq_len(min(input$horizon, nrow(f))), ]
      if (!nrow(h) || !nrow(f)) return(rp_empty_plot("Not enough history to forecast this product"))
      m <- multiplier()
      p <- plotly::plot_ly() |>
        plotly::add_lines(data = h, x = ~dt, y = ~sale_amount, name = "Recorded sales", line = list(color = RP_COL$recorded, width = 1.3)) |>
        plotly::add_lines(data = h, x = ~dt, y = ~latent, name = "Estimated demand", line = list(color = RP_COL$demand, width = 2)) |>
        plotly::add_ribbons(data = f, x = ~dt, ymin = ~lo80, ymax = ~hi80, name = "80% interval (model)", fillcolor = RP_COL$band, line = list(width = 0)) |>
        plotly::add_lines(data = f, x = ~dt, y = ~mean, name = "Model forecast", line = list(color = RP_COL$forecast, width = 2, dash = "dash"))
      if (abs(m$total - 1) > 1e-9)
        p <- p |> plotly::add_lines(data = f, x = ~dt, y = ~mean * m$total, name = "Hypothetical scenario",
                                    line = list(color = RP_COL$scenario, width = 2.6))
      rp_plotly_layout(p, ytitle = UNIT, xtitle = "Date") |>
        plotly::layout(shapes = list(list(type = "line", xref = "x", yref = "paper", x0 = as.character(max(h$dt) + 0.5), x1 = as.character(max(h$dt) + 0.5),
                                          y0 = 0, y1 = 1, line = list(color = RP_COL$muted, dash = "dot", width = 1))))
    })
    output$fc_note <- shiny::renderUI({
      f <- RP$forecast_next[RP$forecast_next$product_id == pid() & RP$forecast_next$.model == RP$manifest$chosen_model, ]
      f <- f[order(f$dt), ][seq_len(min(input$horizon, nrow(f))), ]; shiny::req(nrow(f))
      m <- multiplier(); e <- effect()
      base <- sum(f$mean)
      parts <- list(sprintf("Model forecast: %s units over %d days (80%% daily intervals shown). ", fmt_num(base, 2), nrow(f)))
      if (abs(m$total - 1) > 1e-9) parts <- c(parts, sprintf("Hypothetical scenario: %s units (× %.2f). ", fmt_num(base * m$total, 2), m$total))
      if (input$depth > 0) {
        parts <- c(parts, if (!m$usable) "Too few past promotion days in this category to estimate a promotion association; the promotion slider has no effect here. "
                   else sprintf("A %d%% promotion was historically associated with demand × %.2f (95%% CI %.2f–%.2f) in this category, based on %d promotion days. ",
                                input$depth, m$promo[["mid"]], m$promo[["lo"]], m$promo[["hi"]], e$n_promo_days))
      }
      if (input$horizon > RP$manifest$evaluated_horizon) parts <- c(parts, sprintf("Days beyond %d were not evaluated.", RP$manifest$evaluated_horizon))
      rp_note(parts)
    })

    output$compare <- shiny::renderUI({
      f <- RP$forecast_next[RP$forecast_next$product_id == pid() & RP$forecast_next$.model == RP$manifest$chosen_model, ]
      f <- f[order(f$dt), ][seq_len(min(input$horizon, nrow(f))), ]
      shiny::validate(shiny::need(nrow(f) > 0, "No forecast available for this product."))
      mm <- multiplier(); tot <- mm$total
      h <- RP$daily[RP$daily$product_id == pid(), ]; last7 <- sum(h$latent[h$dt > max(h$dt) - 7])
      f7 <- sum(utils::head(f$mean, 7))
      acts <- function(r) { a <- r$action[r$product_id == pid()]; if (length(a)) paste(a, collapse = "; ") else "–" }
      # product-level rule outcome uses this product's total multiplier (demand change × promotion)
      prod_scen <- if (abs(tot - 1) < 1e-9) base_recs() else build_recs(list(), state$zthr, growth = tot)
      cnt <- function(r, a) length(unique(r$product_id[r$action == a]))
      b <- base_recs(); sc <- scen_recs()
      tile <- function(lbl, base, scen, expl, changed = !identical(base, scen)) htmltools::div(class = if (nchar(scen) > 14) "text",
        htmltools::div(class = "lbl", lbl),
        htmltools::div(class = "vals", htmltools::span(class = "base", base), htmltools::span(class = "arrow", "→"),
                       htmltools::span(class = paste("scen", if (changed) "changed"), scen)),
        htmltools::p(class = "expl", expl))
      htmltools::tagList(htmltools::div(class = "rp-compare",
        tile(sprintf("%s demand, next %d days", plabel(pid()), nrow(f)), fmt_num(sum(f$mean), 2), fmt_num(sum(f$mean) * tot, 2),
             sprintf("80%% interval (model): %s–%s per day on average.", fmt_num(mean(f$lo80), 2), fmt_num(mean(f$hi80), 2))),
        tile("Next 7 days vs last 7 days", fmt_pct(f7 / max(last7, 1e-9), 0), fmt_pct(f7 * tot / max(last7, 1e-9), 0),
             sprintf("Rules flag a surge at ≥ %s and a decline at ≤ %s.", fmt_pct(RP_RULE_DEFAULTS$surge_ratio), fmt_pct(RP_RULE_DEFAULTS$decline_ratio))),
        tile(sprintf("Recommendation for %s", plabel(pid())), acts(b), acts(prod_scen), "Rules R3/R4 re-evaluated with the scenario forecast."),
        tile("Store: products flagged for a possible surge", cnt(b, "Review possible demand surge"), cnt(sc, "Review possible demand surge"),
             sprintf("All products with demand change %+d%% (promotion depth is category-specific, so it is not applied store-wide).", growth_d())),
        tile("Store: products to plan for lower demand", cnt(b, "Plan for lower demand"), cnt(sc, "Plan for lower demand"), "Same store-wide demand change.")),
        rp_note("Baseline values come from the model fitted on observed data. Scenario values are the baseline multiplied by your assumptions; they are what-if arithmetic, not forecasts of what will happen."))
    })

    output$thr_plot <- plotly::renderPlotly({
      z <- RP$daily$z[!is.na(RP$daily$z)]
      grid <- seq(2, 5, by = 0.25)
      x <- data.frame(t = grid, n = vapply(grid, function(t) sum(abs(z) >= t), 0))
      plotly::plot_ly(x, x = ~t, y = ~n, type = "scatter", mode = "lines+markers", line = list(color = RP_COL$accent), marker = list(color = RP_COL$accent),
                      hovertemplate = "|z| ≥ %{x}: %{y} flags<extra></extra>") |>
        rp_plotly_layout(xtitle = "Threshold |z|", ytitle = "Flags", legend = FALSE) |>
        plotly::layout(shapes = list(list(type = "line", x0 = input$zthr, x1 = input$zthr, yref = "paper", y0 = 0, y1 = 1,
                                          line = list(color = RP_COL$gold_dk, width = 1.5, dash = "dot"))))
    })
    output$thr_note <- shiny::renderUI({
      z <- RP$daily$z[!is.na(RP$daily$z)]
      rp_note(sprintf("At |z| ≥ %.1f, %d of %d scored product-days are flagged (%s). Lower thresholds catch more real changes but also more noise. This setting applies across the app.",
                      input$zthr, sum(abs(z) >= input$zthr), length(z), fmt_pct(mean(abs(z) >= input$zthr), 1)))
    })

    ranks <- shiny::reactive({
      w <- list(w_lost = input$w_lost, w_risk = input$w_risk, w_anomaly = input$w_anom)
      a <- build_recs(list(), state$zthr); b <- build_recs(w, state$zthr)
      top <- function(r) { r <- r[!duplicated(r$product_id), ]; data.frame(product_id = r$product_id, rank = seq_len(nrow(r)), action = r$action, priority = r$priority) }
      ta <- top(a); tb <- top(b)
      m <- merge(tb, ta[, c("product_id", "rank")], by = "product_id", suffixes = c("", "_default"))
      m <- m[order(m$rank), ]
      utils::head(m, 12)
    })
    output$rank_tbl <- reactable::renderReactable({
      m <- ranks()
      tb <- data.frame(Rank = m$rank, Product = plabel(m$product_id), Action = m$action, Priority = m$priority,
                       Change = m$rank_default - m$rank)
      reactable::reactable(tb, compact = TRUE, sortable = FALSE, columns = list(
        Rank = reactable::colDef(width = 56), Product = reactable::colDef(width = 86),
        Priority = reactable::colDef(width = 74, format = reactable::colFormat(digits = 2)),
        Change = reactable::colDef(width = 84, cell = function(v) if (v > 0) paste0("▲ ", v) else if (v < 0) paste0("▼ ", abs(v)) else "–",
                                   style = function(v) list(color = if (v > 0) RP_COL$good else if (v < 0) RP_COL$stockout else RP_COL$muted))))
    })
    output$rank_note <- shiny::renderUI(rp_note("▲/▼ = places moved compared with the default weights (all 1). Urgency comes from the rules and is not changed by the weights; the weights only reorder products within the queue."))
  })
}
