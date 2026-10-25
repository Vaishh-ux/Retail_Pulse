# Visual identity ---------------------------------------------------------------------
# Approved brand palette: deep forest green #173B35, warm white #F8FAF8, pure white,
# muted gold #D9A441 (small highlights only), sage green #DCEBE3 (positive / low risk),
# alert red #DC5555 (critical only). Amber #C98A12 is used for medium warnings.
#
# Chart roles are fixed so colour always means the same thing:
#   recorded sales = slate grey, estimated demand = forest green, forecast = forest dashed + band,
#   stockout = red, promotion = light gold shading, anomaly = plum ring, scenario = gold.
RP_COL <- list(
  forest = "#173B35", forest2 = "#2F6B5E", warm = "#F8FAF8", white = "#FFFFFF",
  gold = "#D9A441", gold_dk = "#A87A1E", sage = "#DCEBE3", red = "#DC5555", amber = "#C98A12",
  ink = "#16231F", ink2 = "#4C5A55", muted = "#86928D", grid = "#E6ECE8", line = "#DDE5E0",
  surface = "#FFFFFF", page = "#F8FAF8", brand = "#173B35", accent = "#2F6B5E", accent_lt = "#DCEBE3",
  recorded = "#5E6B66", demand = "#2F6B5E", forecast = "#2F6B5E", band = "rgba(47,107,94,0.16)",
  stockout = "#DC5555", stockout_lt = "rgba(220,85,85,0.16)", promo = "#D9A441",
  promo_lt = "rgba(217,164,65,0.18)", anomaly = "#7B4F8E", good = "#2F7A55", warn = "#C98A12",
  scenario = "#D9A441", baseline = "#A9B5B0"
)
# Diverging scale for "below / above normal": forest green below, gold above (red is
# reserved for stockouts and critical alerts).
RP_DIVERGING <- list(c(0, "#0F2E29"), c(0.2, "#2F6B5E"), c(0.36, "#B9D6C8"), c(0.44, "#F4F6F4"), c(0.56, "#F4F6F4"),
                     c(0.64, "#F1DDAE"), c(0.8, "#D9A441"), c(1, "#8A5F12"))
RP_SEQ <- list(c(0, "#F3F7F5"), c(0.35, "#B9D6C8"), c(1, "#173B35"))

rp_theme <- function() {
  bslib::bs_theme(
    version = 5, bg = RP_COL$page, fg = RP_COL$ink, primary = RP_COL$forest, secondary = RP_COL$ink2,
    success = RP_COL$good, danger = RP_COL$red, warning = RP_COL$amber, info = RP_COL$forest2,
    base_font = bslib::font_google("Inter", local = FALSE),
    heading_font = bslib::font_google("Plus Jakarta Sans", local = FALSE),
    "border-radius" = "0.75rem", "border-radius-sm" = "0.5rem", "border-radius-lg" = "1rem",
    "card-border-color" = RP_COL$line, "navbar-bg" = RP_COL$forest,
    "link-color" = RP_COL$forest2, "input-border-color" = "#CFD9D4", "focus-ring-color" = "rgba(217,164,65,.35)",
    font_scale = 0.95
  )
}

rp_config_bar <- function(p) plotly::config(p, displaylogo = FALSE,
  modeBarButtonsToRemove = c("lasso2d", "select2d", "autoScale2d", "toggleSpikelines"))

rp_plotly_layout <- function(p, ytitle = NULL, xtitle = NULL, legend = TRUE, hovermode = "x unified", config = TRUE) {
  p <- plotly::layout(p,
    font = list(family = "Inter, system-ui, sans-serif", size = 12, color = RP_COL$ink2),
    paper_bgcolor = "rgba(0,0,0,0)", plot_bgcolor = "rgba(0,0,0,0)",
    margin = list(l = 56, r = 16, t = 16, b = 44),
    xaxis = list(title = xtitle, gridcolor = RP_COL$grid, zeroline = FALSE, linecolor = "#C9D3CE"),
    yaxis = list(title = ytitle, gridcolor = RP_COL$grid, zeroline = FALSE, rangemode = "tozero"),
    hovermode = hovermode,
    hoverlabel = list(bgcolor = "#FFFFFF", bordercolor = RP_COL$line, font = list(color = RP_COL$ink, size = 12)),
    legend = if (legend) list(orientation = "h", x = 0, y = 1.12, font = list(size = 11)) else NULL,
    showlegend = legend
  )
  if (config) rp_config_bar(p) else p
}

rp_empty_plot <- function(msg = "No data for this selection") {
  plotly::plot_ly(type = "scatter", mode = "markers") |>
    plotly::layout(xaxis = list(visible = FALSE), yaxis = list(visible = FALSE),
                   annotations = list(list(text = msg, showarrow = FALSE, font = list(size = 14, color = RP_COL$muted))),
                   paper_bgcolor = "rgba(0,0,0,0)", plot_bgcolor = "rgba(0,0,0,0)") |>
    plotly::config(displayModeBar = FALSE)
}

# A short interpretation line under a chart
rp_note <- function(...) htmltools::tags$p(class = "rp-note", ...)
rp_badge <- function(text, kind = "neutral") htmltools::tags$span(class = paste("rp-badge", paste0("rp-", kind)), text)
urgency_kind <- function(u) switch(u, High = "critical", Medium = "warning", Low = "neutral", Info = "info", "neutral")
rp_card_title <- function(title, sub = NULL, icon = NULL) htmltools::div(class = "rp-card-title",
  if (!is.null(icon)) htmltools::span(class = "rp-ct-icon", shiny::icon(icon)), htmltools::span(title),
  if (!is.null(sub)) htmltools::span(class = "rp-sub", sub))

# KPI tile: white card, icon, value, optional change chip; `tone` adds a thin accent
# only when the data justifies it (critical = red, warning = amber, good = sage).
rp_kpi <- function(title, value, sub = NULL, icon = "chart-line", tone = "neutral", delta = NULL, delta_good = NA) {
  chip <- if (!is.null(delta) && !is.na(delta)) {
    cls <- if (is.na(delta_good)) "flat" else if (delta_good) "up-good" else "up-bad"
    htmltools::span(class = paste("rp-delta", cls), sprintf("%s%s vs previous period", if (delta >= 0) "▲ " else "▼ ", fmt_pct(abs(delta), 0)))
  }
  htmltools::div(class = paste("rp-kpi", paste0("rp-kpi-", tone)),
    htmltools::div(class = "rp-kpi-top", htmltools::span(class = "rp-kpi-icon", shiny::icon(icon)), htmltools::span(class = "rp-kpi-title", title)),
    htmltools::div(class = "rp-kpi-value", value),
    if (!is.null(sub)) htmltools::p(class = "rp-kpi-sub", sub), chip)
}
tone_for <- function(x, warn, crit) if (is.na(x)) "neutral" else if (x >= crit) "critical" else if (x >= warn) "warning" else "good"
