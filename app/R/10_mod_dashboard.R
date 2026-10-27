# Page 1 - Dashboard -----------------------------------------------------------------------
# Four KPIs, one chart (recorded sales vs estimated demand), one list of products that
# need attention, and a short plain-language summary. Period and category filters apply to
# the KPIs, chart and summary; the attention list is "as of the latest day" (the rules
# look at the last 7 days) and says so.

DASH_ACTIONS <- c("Consider replenishing earlier", "Review possible demand surge", "Investigate unexplained sales drop",
                  "Plan for lower demand", "Use caution: forecast unreliable")

mod_dashboard_ui <- function(id, RP) {
  ns <- shiny::NS(id)
  m <- RP$manifest
  rng <- range(RP$daily$dt)
  cats <- sort(unique(RP$products$first_category_id))
  htmltools::tagList(
    htmltools::div(class = "rp-hero",
      htmltools::div(
        htmltools::div(class = "rp-eyebrow", sprintf("Store %s · %d products · %s", m$store_id, m$products,
                                                     if (identical(m$mode, "synthetic")) "synthetic demo data" else "FreshRetailNet-50K")),
        htmltools::h1("Dashboard"),
        htmltools::p(sprintf("Sales data from %s to %s. Start with the products that need attention.",
                             format(rng[1], "%d %b %Y"), format(rng[2], "%d %b %Y")))),
      htmltools::div(class = "rp-filters",
        shiny::selectInput(ns("period"), "Period", width = "160px", selected = "28",
          choices = c("Last 7 days" = "7", "Last 14 days" = "14", "Last 4 weeks" = "28", "Last 8 weeks" = "56", "All data" = "all")),
        shiny::selectInput(ns("cat"), "Category", width = "170px",
          choices = c("All categories" = "", stats::setNames(cats, paste("Category", cats)))))),
    shiny::uiOutput(ns("kpis")),
    bslib::layout_columns(col_widths = bslib::breakpoints(sm = 12, lg = c(8, 4)),
      bslib::card(full_screen = TRUE,
        bslib::card_header(rp_card_title("Sales and estimated demand", "Daily totals · red bars = hours out of stock", "chart-line")),
        plotly::plotlyOutput(ns("trend"), height = "320px"),
        shiny::uiOutput(ns("trend_note"))),
      bslib::card(
        bslib::card_header(rp_card_title("What this means", "for the selected period", "lightbulb")),
        shiny::uiOutput(ns("summary")))),
    bslib::card(id = ns("attention_card"),
      bslib::card_header(rp_card_title("Products that need attention", "as of the latest day · click a row to see the product", "bell")),
      htmltools::div(class = "rp-filters rp-filters-inline",
        shiny::selectInput(ns("action"), NULL, width = "300px",
          choices = c("All suggested actions" = "", stats::setNames(DASH_ACTIONS, DASH_ACTIONS)))),
      reactable::reactableOutput(ns("attention")),
      rp_note("Suggestions come from simple, documented rules (see Data & Model Results → Advanced details). ",
              "They do not give order quantities: the data has no stock levels, lead times or costs."))
  )
}

mod_dashboard_server <- function(id, RP, state, recs_r, anoms_r, goto_product, goto_results = function(tab) NULL) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns
    rng <- range(RP$daily$dt); last_dt <- rng[2]
    sid <- as.character(RP$manifest$store_id)

    period <- shiny::reactive({
      p <- input$period %||% "28"
      c(if (p == "all") rng[1] else max(rng[1], last_dt - as.integer(p) + 1), last_dt)
    })
    cat_ids <- shiny::reactive({
      if (nzchar(input$cat %||% "")) RP$products$product_id[RP$products$first_category_id == as.integer(input$cat)] else RP$products$product_id
    })
    d_cat <- shiny::reactive(RP$daily[RP$daily$product_id %in% cat_ids(), ])
    d_per <- shiny::reactive({ p <- period(); x <- d_cat(); x[x$dt >= p[1] & x$dt <= p[2], ] })
    d_prev <- shiny::reactive({ p <- period(); n <- as.integer(p[2] - p[1]) + 1; x <- d_cat(); x[x$dt >= p[1] - n & x$dt < p[1], ] })
    recs_cat <- shiny::reactive({ r <- recs_r(); r[r$product_id %in% cat_ids(), ] })
    lab <- shiny::reactive({ p <- period(); sprintf("%s – %s", format(p[1], "%d %b"), format(p[2], "%d %b %Y")) })
    key <- shiny::reactive(list(sid, period(), input$cat %||% ""))

    output$kpis <- shiny::renderUI({
      x <- d_per(); pv <- d_prev()
      shiny::validate(shiny::need(nrow(x) > 0, "No sales data for this period and category."))
      chg <- function(a, b) if (is.na(b) || b <= 0) NA else a / b - 1
      rec <- sum(x$sale_amount); rec_p <- if (nrow(pv)) sum(pv$sale_amount) else NA
      dem <- sum(x$latent); dem_p <- if (nrow(pv)) sum(pv$latent) else NA
      unmet <- sum(x$lost) / max(dem, 1e-9); unmet_p <- if (nrow(pv)) sum(pv$lost) / max(sum(pv$latent), 1e-9) else NA
      r <- recs_cat()
      attn <- length(unique(r$product_id[r$urgency %in% c("High", "Medium")]))
      high <- length(unique(r$product_id[r$urgency == "High"]))
      d1 <- chg(rec, rec_p); d2 <- chg(dem, dem_p); d3 <- chg(unmet, unmet_p)
      # each card opens the analysis behind it
      click <- function(tag, target, tip) htmltools::tagAppendAttributes(tag, class = "rp-kpi-click", role = "button", tabindex = "0",
                                                                         `data-rp-input` = ns("kpi"), `data-rp-value` = target, title = tip)
      htmltools::div(class = "rp-kpis rp-kpis-4",
        click(rp_kpi("Recorded sales", fmt_num(rec, 0), sprintf("%s · normalised units (the dataset hides real quantities)", lab()),
               "cart-shopping", "neutral", d1, if (is.na(d1)) NA else d1 >= 0), "eda", "Open: Exploring the data"),
        click(rp_kpi("Estimated demand", fmt_num(dem, 0), "What customers probably wanted, including sales missed while out of stock (an estimate)",
               "chart-column", "neutral", d2, if (is.na(d2)) NA else d2 >= 0), "fc", "Open: how demand is estimated and forecast"),
        click(rp_kpi("Demand missed", fmt_pct(unmet, 1), sprintf("about %s units lost to empty shelves", fmt_num(sum(x$lost), 0)),
               "box-open", tone_for(unmet, 0.05, 0.15), d3, if (is.na(d3)) NA else d3 <= 0), "risk", "Open: stockout risk"),
        click(rp_kpi("Products needing attention", attn, sprintf("%d urgent · based on the last 7 days of data", high),
               "triangle-exclamation", if (high > 0) "warning" else "good"), "attention", "Jump to the list of products"))
    }) |> shiny::bindCache(key(), "kpis")

    agg <- shiny::reactive({
      x <- d_per(); shiny::req(nrow(x))
      a <- stats::aggregate(cbind(observed = sale_amount, latent = latent, stockout_hours = stock_h) ~ dt + split, x, sum)
      a[order(a$dt), ]
    })
    output$trend <- plotly::renderPlotly(ch_store_trend(agg())) |> shiny::bindCache(key(), "trend")
    output$trend_note <- shiny::renderUI({
      a <- agg(); gap <- sum(a$latent - a$observed)
      rp_note(sprintf("The green line is estimated demand and the grey line is what was actually sold. The gap (%s units, %s of demand) is sales missed because products were out of stock. ",
                      fmt_num(gap, 0), fmt_pct(gap / max(sum(a$latent), 1e-9), 1)),
              "Estimated demand is a model estimate, not a measurement.")
    }) |> shiny::bindCache(key(), "trend_note")

    output$summary <- shiny::renderUI({
      x <- d_per(); pv <- d_prev(); shiny::req(nrow(x))
      items <- list()
      add <- function(icon, kind, ...) items[[length(items) + 1]] <<- htmltools::div(class = "rp-insight",
        htmltools::span(class = paste("rp-insight-icon", kind), shiny::icon(icon)), htmltools::p(...))
      byp <- stats::aggregate(cbind(lost, latent) ~ product_id, x, sum)
      share <- sum(x$lost) / max(sum(x$latent), 1e-9); so <- sum(x$stock_h) / (16 * nrow(x))
      add("box-open", if (share >= 0.15) "bad" else if (share >= 0.05) "warn" else "",
          htmltools::strong(sprintf("Empty shelves cost about %s of demand. ", fmt_pct(share, 0))),
          sprintf("Products were out of stock in %s of opening hours (06:00–22:00); %d of %d products lost more than a fifth of their demand.",
                  fmt_pct(so, 0), sum(byp$lost / pmax(byp$latent, 1e-9) > 0.2), nrow(byp)))
      if (nrow(pv)) {
        ch <- sum(x$latent) / max(sum(pv$latent), 1e-9) - 1
        add(if (ch >= 0) "arrow-trend-up" else "arrow-trend-down", "gold",
            htmltools::strong(sprintf("Demand is %s %s ", if (ch >= 0) "up" else "down", fmt_pct(abs(ch), 0))),
            sprintf("compared with the %d days before.", as.integer(diff(period())) + 1))
      }
      w <- RP$store_weekday_hour
      if (NROW(w)) {
        by_h <- stats::aggregate(mean_sales ~ hour, w, mean)
        so_h <- RP$sellout_summary$median_sellout_hour[RP$sellout_summary$product_id %in% unique(x$product_id)]
        add("clock", "", htmltools::strong(sprintf("Busiest hour: %02d:00. ", by_h$hour[which.max(by_h$mean_sales)])),
            if (sum(!is.na(so_h))) sprintf("Products that often sell out are usually gone by about %02.0f:00, so restock before the evening.", stats::median(so_h, na.rm = TRUE))
            else "Most products do not sell out on a typical day.")
      }
      htmltools::div(class = "rp-insights", items)
    }) |> shiny::bindCache(key(), "summary")

    output$attention <- reactable::renderReactable({
      r <- recs_cat(); a <- input$action %||% ""
      r <- if (nzchar(a)) r[r$action == a, ] else r[r$action != "Maintain current approach" & !duplicated(r$product_id), ]
      r <- r[order(-r$priority), ]
      if (!nrow(r)) return(reactable::reactable(data.frame(Message = "No products currently need this action.")))
      tb <- data.frame(product_id = r$product_id, Product = plabel(r$product_id),
                       Category = RP$products$category[match(r$product_id, RP$products$product_id)],
                       `Suggested action` = r$action, Why = r$reason, Urgency = r$urgency, check.names = FALSE)
      reactable::reactable(tb, compact = TRUE, highlight = TRUE, searchable = TRUE, defaultPageSize = 8,
        rowStyle = list(cursor = "pointer"), language = reactable::reactableLang(searchPlaceholder = "Search products or reasons…"),
        onClick = reactable::JS(sprintf("function(rowInfo){ Shiny.setInputValue('%s', rowInfo.values.product_id, {priority: 'event'}) }", ns("pick"))),
        columns = list(product_id = reactable::colDef(show = FALSE),
                       Product = reactable::colDef(width = 86, style = list(fontWeight = 700, color = RP_COL$forest)),
                       Category = reactable::colDef(width = 120),
                       `Suggested action` = reactable::colDef(minWidth = 170),
                       Why = reactable::colDef(minWidth = 260, sortable = FALSE, style = list(fontSize = "0.82rem", color = RP_COL$ink2)),
                       Urgency = reactable::colDef(width = 96, cell = function(v) rp_badge(v, urgency_kind(v)))))
    }) |> shiny::bindCache(sid, input$cat %||% "", input$action %||% "", "attention")
    shiny::observeEvent(input$pick, goto_product(input$pick))
    shiny::observeEvent(input$kpi, {
      t <- input$kpi$value
      if (t == "attention") { shiny::updateSelectInput(session, "action", selected = ""); session$sendCustomMessage("rp-scroll", list(id = ns("attention_card"))) }
      else goto_results(t)
    })
  })
}
