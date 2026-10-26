# Chart builders (plotly) ----------------------------------------------------------------
# Every function returns a plotly object and handles empty input gracefully.

UNIT <- "Sales (normalised units)"

shade_shapes <- function(dates, color, y0 = 0, y1 = 1, yref = "paper") {
  if (!length(dates)) return(list())
  dates <- sort(unique(as.Date(dates)))
  grp <- cumsum(c(1, diff(dates) != 1))
  unname(lapply(split(dates, grp), function(g) list(type = "rect", xref = "x", yref = yref,
    x0 = as.character(min(g) - 0.5), x1 = as.character(max(g) + 0.5), y0 = y0, y1 = y1,
    fillcolor = color, line = list(width = 0), layer = "below")))
}

# Product trend: recorded vs estimated demand, stockouts, promotions, anomalies, forecast
ch_trend <- function(dp, an = NULL, fc = NULL, horizon = 7, cmp = NULL, cmp_label = NULL) {
  if (!NROW(dp)) return(rp_empty_plot())
  dp <- dp[order(dp$dt), ]
  dp$ma7 <- as.numeric(stats::filter(dp$latent, rep(1 / 7, 7), sides = 1))
  so <- dp[dp$stock_h >= 4, ]
  p <- plotly::plot_ly(dp, x = ~dt) |>
    plotly::add_lines(y = ~sale_amount, name = "Recorded sales", line = list(color = RP_COL$recorded, width = 1.4),
                      hovertemplate = "Recorded %{y:.2f}<extra></extra>") |>
    plotly::add_lines(y = ~latent, name = "Estimated demand", line = list(color = RP_COL$demand, width = 2),
                      hovertemplate = "Estimated demand %{y:.2f}<extra></extra>") |>
    plotly::add_lines(y = ~ma7, name = "7-day average (est. demand)", line = list(color = RP_COL$demand, width = 1, dash = "dot"),
                      hovertemplate = "7-day avg %{y:.2f}<extra></extra>")
  if (NROW(cmp)) p <- p |> plotly::add_lines(data = cmp[order(cmp$dt), ], x = ~dt, y = ~latent, name = paste("Estimated demand:", cmp_label),
      line = list(color = RP_COL$gold_dk, width = 1.6, dash = "dot"), hovertemplate = paste0(cmp_label, " est. demand %{y:.2f}<extra></extra>"))
  if (nrow(so)) p <- p |> plotly::add_markers(data = so, y = ~sale_amount, name = "Stockout day (4+ h out)",
      marker = list(symbol = "circle-open", size = 9, color = RP_COL$stockout, line = list(width = 2)),
      text = ~paste0(stock_h, " of 16 trading hours out of stock"), hovertemplate = "%{text}<extra></extra>")
  if (NROW(an)) p <- p |> plotly::add_markers(data = an, x = ~dt, y = ~observed, name = "Anomaly",
      marker = list(symbol = "diamond-open", size = 11, color = RP_COL$anomaly, line = list(width = 2)),
      text = ~paste0(cause, " (z = ", z, ")"), hovertemplate = "%{text}<extra></extra>")
  shapes <- shade_shapes(dp$dt[dp$promo == 1], RP_COL$promo_lt)
  if (NROW(fc)) {
    fc <- fc[order(fc$dt), ][seq_len(min(horizon, nrow(fc))), ]
    p <- p |>
      plotly::add_ribbons(data = fc, x = ~dt, ymin = ~lo80, ymax = ~hi80, name = "80% prediction interval",
                          fillcolor = RP_COL$band, line = list(width = 0), hoverinfo = "skip") |>
      plotly::add_lines(data = fc, x = ~dt, y = ~mean, name = "Forecast (estimated demand)",
                        line = list(color = RP_COL$forecast, width = 2, dash = "dash"),
                        hovertemplate = "Forecast %{y:.2f}<extra></extra>")
    shapes <- c(shapes, list(list(type = "line", xref = "x", yref = "paper", x0 = as.character(max(dp$dt) + 0.5),
                                  x1 = as.character(max(dp$dt) + 0.5), y0 = 0, y1 = 1,
                                  line = list(color = RP_COL$muted, width = 1, dash = "dot"))))
  }
  top <- rp_plotly_layout(p, ytitle = UNIT, config = FALSE) |> plotly::layout(shapes = shapes)
  bot <- plotly::plot_ly(dp, x = ~dt, y = ~stock_h, type = "bar", name = "Stockout hours",
                         marker = list(color = RP_COL$stockout), showlegend = FALSE,
                         hovertemplate = "%{y} h out of stock<extra></extra>") |>
    plotly::layout(yaxis = list(title = "Out (h)", range = c(0, 16), dtick = 8, gridcolor = RP_COL$grid),
                   xaxis = list(title = "Date"))
  plotly::subplot(top, bot, nrows = 2, heights = c(0.78, 0.22), shareX = TRUE, titleY = TRUE, margin = 0.03) |>
    rp_config_bar() |>
    plotly::layout(legend = list(orientation = "h", x = 0, y = 1.1, font = list(size = 11)),
                   annotations = if (NROW(fc)) list(list(x = as.character(max(dp$dt)), y = 1, xref = "x", yref = "paper",
                     text = "data ends | forecast", showarrow = FALSE, xanchor = "center", yanchor = "bottom",
                     font = list(size = 10, color = RP_COL$muted))) else list())
}

# Store-level daily totals
ch_store_trend <- function(sd) {
  if (!NROW(sd)) return(rp_empty_plot())
  sd$dt <- as.Date(sd$dt); sd$x <- format(sd$dt, "%Y-%m-%d")
  p <- plotly::plot_ly(sd, x = ~x) |>
    plotly::add_lines(y = ~observed, name = "Recorded sales", line = list(color = RP_COL$recorded, width = 1.5)) |>
    plotly::add_lines(y = ~latent, name = "Estimated demand", line = list(color = RP_COL$demand, width = 2.4)) |>
    plotly::add_bars(y = ~stockout_hours, name = "Stockout hours (right axis)", yaxis = "y2",
                     marker = list(color = "rgba(220,85,85,0.22)", line = list(width = 0)),
                     hovertemplate = "%{y} stockout hours<extra></extra>")
  rp_plotly_layout(p, ytitle = "Store total (normalised units)", xtitle = "Date") |>
    plotly::layout(xaxis = list(type = "date", gridcolor = RP_COL$grid), yaxis2 = list(overlaying = "y", side = "right", showgrid = FALSE, title = "Stockout hours", range = c(0, 3 * max(sd$stockout_hours, 1))),
                   bargap = 0.35,
                   shapes = shade_shapes(sd$dt[sd$split == "eval"], "rgba(137,135,129,0.10)"),
                   margin = list(r = 56))
}

# Product x date deviation heatmap (the theory case study's Visualization 2)
# mode = "z": deviation from the product's own weekday-adjusted baseline (robust z)
# mode = "demand": estimated demand relative to the product's own mean in the window
# mode = "stockout": trading hours out of stock (0-16)
ch_heatmap <- function(daily, labels, days = 42, z_cap = 4, source = "heat", mode = "z", start = NULL, end = NULL) {
  if (!NROW(daily)) return(rp_empty_plot())
  last <- end %||% max(daily$dt)
  first <- start %||% (last - days + 1)
  x <- daily[daily$dt >= first & daily$dt <= last, ]
  if (!nrow(x)) return(rp_empty_plot("No days in the selected period"))
  prods <- sort(unique(x$product_id))
  dates <- sort(unique(x$dt))
  z <- matrix(NA_real_, length(prods), length(dates))
  st <- matrix(0, length(prods), length(dates))
  dm <- matrix(NA_real_, length(prods), length(dates))
  ri <- match(x$product_id, prods); ci <- match(x$dt, dates)
  z[cbind(ri, ci)] <- pmax(-z_cap, pmin(z_cap, x$z)); st[cbind(ri, ci)] <- x$stock_h
  dm[cbind(ri, ci)] <- x$latent
  rel <- dm / pmax(rowMeans(dm, na.rm = TRUE), 1e-9)
  ylab <- unname(labels[as.character(prods)])
  stock_txt <- ifelse(st >= 4, sprintf("%d h out of stock", st), ifelse(st > 0, sprintf("%d h out of stock", st), "in stock all trading hours"))
  hover <- matrix(sprintf("<b>%s</b> · %s<br>Estimated demand %s (%s of its usual level)<br>Deviation z = %s<br>%s",
                          rep(ylab, length(dates)), rep(format(dates, "%a %d %b"), each = length(prods)),
                          ifelse(is.na(dm), "n/a", sprintf("%.2f", dm)), ifelse(is.na(rel), "n/a", sprintf("%.0f%%", 100 * rel)),
                          ifelse(is.na(z), "n/a", sprintf("%.1f", z)), stock_txt),
                  nrow = length(prods))
  so <- which(st >= 4, arr.ind = TRUE)
  if (mode == "stockout") {
    zz <- st; zmin <- 0; zmax <- 16; cs <- list(c(0, "#F4F6F4"), c(0.25, "#F3D3CC"), c(1, RP_COL$red))
    cb <- list(title = list(text = "Hours out", side = "right"), thickness = 10, len = 0.6, tickvals = c(0, 4, 8, 12, 16))
  } else if (mode == "demand") {
    zz <- pmin(rel, 2.5); zmin <- 0; zmax <- 2.5; cs <- RP_SEQ
    cb <- list(title = list(text = "× usual", side = "right"), thickness = 10, len = 0.6, tickvals = c(0, 0.5, 1, 1.5, 2, 2.5),
               ticktext = c("0", "0.5×", "1× usual", "1.5×", "2×", "≥2.5×"))
  } else {
    zz <- z; zmin <- -z_cap; zmax <- z_cap; cs <- RP_DIVERGING
    cb <- list(title = list(text = "Robust z", side = "right"), thickness = 10, len = 0.6,
               tickvals = c(-4, -2, 0, 2, 4), ticktext = c("≤ −4 below", "−2", "0 normal", "+2", "≥ +4 above"))
  }
  p <- plotly::plot_ly(source = source) |>
    plotly::add_heatmap(x = as.character(dates), y = ylab, z = zz, zmin = zmin, zmax = zmax, colorscale = cs,
                        text = hover, hoverinfo = "text", xgap = 1.5, ygap = 1.5, colorbar = cb)
  if (nrow(so) && mode != "stockout") p <- p |> plotly::add_markers(x = as.character(dates[so[, 2]]), y = ylab[so[, 1]], name = "4+ h out of stock",
      marker = list(symbol = "x-thin", size = 7, line = list(width = 1.6, color = if (mode == "z") "#ffffff" else RP_COL$red)), hoverinfo = "skip", showlegend = TRUE)
  rp_plotly_layout(p, hovermode = "closest") |>
    plotly::layout(xaxis = list(type = "category", tickangle = 0, nticks = 7, showgrid = FALSE),
                   yaxis = list(autorange = "reversed", showgrid = FALSE, tickfont = list(size = 10), rangemode = NULL,
                                categoryorder = "array", categoryarray = ylab),
                   legend = list(orientation = "h", x = 0, y = -0.12), margin = list(l = 56, r = 8, t = 8, b = 56)) |>
    plotly::event_register("plotly_click")
}

ch_weekday_hour <- function(wdh, value = "mean_sales") {
  if (!NROW(wdh)) return(rp_empty_plot())
  days <- c("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
  m <- matrix(NA_real_, 7, 24); m[cbind(wdh$weekday, wdh$hour + 1)] <- wdh[[value]]
  plotly::plot_ly(x = sprintf("%02d", 0:23), y = days, z = m, type = "heatmap",
                  colorscale = RP_SEQ, xgap = 1, ygap = 1,
                  hovertemplate = "%{y} %{x}:00<br>mean %{z:.3f} per in-stock hour<extra></extra>",
                  colorbar = list(title = list(text = "Mean sales / h"), thickness = 10)) |>
    rp_plotly_layout(xtitle = "Hour of day", legend = FALSE, hovermode = "closest") |>
    plotly::layout(yaxis = list(autorange = "reversed", rangemode = NULL, showgrid = FALSE), xaxis = list(showgrid = FALSE))
}

ch_instock_vs_out <- function(x) {
  if (!NROW(x)) return(rp_empty_plot())
  plotly::plot_ly(x, x = ~hour, y = ~mean_sales, color = ~status, type = "bar",
                  colors = c("In stock" = RP_COL$accent, "Out of stock" = RP_COL$stockout),
                  hovertemplate = "%{x}:00 · %{y:.3f}<extra>%{fullData.name}</extra>") |>
    rp_plotly_layout(ytitle = "Mean recorded sales per hour", xtitle = "Hour of day (trading hours)") |>
    plotly::layout(barmode = "group")
}

ch_sellout <- function(cur) {
  if (!NROW(cur)) return(rp_empty_plot("This product never sold out in the data"))
  cols <- c(weekday = RP_COL$forest2, weekend = RP_COL$gold_dk)
  p <- plotly::plot_ly()
  for (w in unique(cur$weektype)) {
    g <- cur[cur$weektype == w, ]
    p <- p |> plotly::add_lines(x = g$hour, y = g$surv, name = paste0(tools::toTitleCase(w), "s"), line = list(shape = "hv", width = 2, color = cols[[w]]),
                                hovertemplate = "%{x}:00 · %{y:.0%} still in stock<extra></extra>")
  }
  rp_plotly_layout(p, ytitle = "Share of days still in stock", xtitle = "Hour of day") |>
    plotly::layout(yaxis = list(range = c(0, 1.02), tickformat = ".0%"), xaxis = list(range = c(6, 22), dtick = 2))
}

ch_model_bars <- function(cv, ev) {
  if (!NROW(cv) && !NROW(ev)) return(rp_empty_plot())
  x <- dplyr::bind_rows(dplyr::mutate(cv, window = "Rolling-origin CV (training)"), dplyr::mutate(ev, window = "Hold-out (evaluation week)"))
  x$model <- ifelse(x$.model == "ets", "ETS", "Seasonal naive")
  plotly::plot_ly(x, x = ~window, y = ~WAPE, color = ~model, type = "bar",
                  colors = c("ETS" = RP_COL$accent, "Seasonal naive" = RP_COL$baseline),
                  text = ~sprintf("%.1f%%", 100 * WAPE), textposition = "outside",
                  hovertemplate = "%{fullData.name}: WAPE %{y:.1%}<extra></extra>") |>
    rp_plotly_layout(ytitle = "WAPE on in-stock days (lower is better)", xtitle = "") |>
    plotly::layout(barmode = "group", yaxis = list(tickformat = ".0%", range = c(0, max(x$WAPE, na.rm = TRUE) * 1.2)),
                   xaxis = list(title = ""))
}

ch_actual_vs_fc <- function(ev) {
  if (!NROW(ev)) return(rp_empty_plot())
  ev <- ev[order(ev$dt), ]
  a <- ev[ev$.model == ev$.model[1], ]
  p <- plotly::plot_ly()
  for (m in unique(ev$.model)) {
    g <- ev[ev$.model == m, ]
    p <- p |> plotly::add_lines(data = g, x = ~dt, y = ~mean, name = ifelse(m == "ets", "ETS forecast", "Seasonal-naive forecast"),
                                line = list(dash = "dash", width = 2, color = if (m == "ets") RP_COL$forest2 else RP_COL$baseline))
  }
  p |>
    plotly::add_markers(data = a, x = ~dt, y = ~sale_amount, name = "Recorded sales",
                        marker = list(color = ifelse(a$any_stockout == 1, "#ffffff", RP_COL$recorded), size = 9,
                                      line = list(color = ifelse(a$any_stockout == 1, RP_COL$stockout, RP_COL$recorded), width = 2)),
                        text = ifelse(a$any_stockout == 1, "had a stockout: excluded from scoring", "in stock: scored"),
                        hovertemplate = "%{y:.2f} (%{text})<extra></extra>") |>
    rp_plotly_layout(ytitle = UNIT, xtitle = "Date")
}

ch_latent_scatter <- function(v) {
  if (!NROW(v)) return(rp_empty_plot())
  mx <- max(c(v$actual, v$estimate), na.rm = TRUE)
  plotly::plot_ly(v, x = ~actual, y = ~estimate, type = "scatter", mode = "markers", name = "Profile estimate",
                  marker = list(color = "rgba(47,107,94,0.35)", size = 5),
                  hovertemplate = "actual %{x:.2f} · estimate %{y:.2f}<extra></extra>") |>
    plotly::add_markers(x = ~actual, y = ~observed_only, name = "Observed sales only",
                        marker = list(color = "rgba(94,107,102,0.25)", size = 4)) |>
    plotly::add_lines(x = c(0, mx), y = c(0, mx), name = "Perfect estimate", line = list(color = RP_COL$muted, dash = "dot", width = 1),
                      hoverinfo = "skip", inherit = FALSE) |>
    rp_plotly_layout(ytitle = "Estimated day total", xtitle = "Actual day total (hidden hours known)", hovermode = "closest")
}

ch_latent_cutoff <- function(b) {
  if (!NROW(b)) return(rp_empty_plot())
  plotly::plot_ly(b, x = ~cutoff_hour) |>
    plotly::add_lines(y = ~wape_profile, name = "Profile method", line = list(color = RP_COL$accent, width = 2)) |>
    plotly::add_lines(y = ~wape_observed, name = "Observed sales only", line = list(color = RP_COL$muted, width = 2, dash = "dash")) |>
    rp_plotly_layout(ytitle = "WAPE", xtitle = "Simulated stockout starts at (hour)") |>
    plotly::layout(yaxis = list(tickformat = ".0%"))
}

ch_calibration <- function(cal) {
  if (!NROW(cal)) return(rp_empty_plot())
  plotly::plot_ly(cal, x = ~mean_pred, y = ~observed_rate, type = "scatter", mode = "lines+markers", name = "Logistic model",
                  marker = list(size = ~pmax(6, sqrt(n) * 1.5), color = RP_COL$accent), line = list(color = RP_COL$accent),
                  text = ~paste0("n = ", n), hovertemplate = "predicted %{x:.0%} · observed %{y:.0%} (%{text})<extra></extra>") |>
    plotly::add_lines(x = c(0, 1), y = c(0, 1), name = "Perfect calibration", line = list(color = RP_COL$muted, dash = "dot", width = 1),
                      inherit = FALSE, hoverinfo = "skip") |>
    rp_plotly_layout(ytitle = "Observed event rate", xtitle = "Predicted probability", hovermode = "closest") |>
    plotly::layout(xaxis = list(range = c(0, 1), tickformat = ".0%"), yaxis = list(range = c(0, 1), tickformat = ".0%"))
}

ch_coefs <- function(co) {
  co <- co[co$term != "(Intercept)", ]
  if (!NROW(co)) return(rp_empty_plot())
  nice <- c(so_rate7 = "Share of last 7 days with stockout", so_hours7 = "Mean stockout hours, last 7 days",
            yest_event = "Stockout event yesterday", demand_ratio = "Recent demand change (7d / 28d)",
            promo = "Promotion on the day", holiday_flag = "Holiday", weekend = "Weekend")
  co$label <- unname(nice[co$term]); co$label[is.na(co$label)] <- co$term[is.na(co$label)]
  co <- co[order(co$odds_ratio), ]
  plotly::plot_ly(co, y = ~label, x = ~odds_ratio, type = "scatter", mode = "markers",
                  error_x = list(type = "data", symmetric = FALSE, array = ~or_hi95 - odds_ratio, arrayminus = ~odds_ratio - or_lo95,
                                 color = RP_COL$ink2, thickness = 1.2),
                  marker = list(color = RP_COL$accent, size = 9),
                  hovertemplate = "%{y}: odds ratio %{x:.2f}<extra></extra>") |>
    rp_plotly_layout(xtitle = "Odds ratio (log scale, 95% CI)", legend = FALSE, hovermode = "closest") |>
    plotly::layout(xaxis = list(type = "log", title = "Odds ratio (log scale, 95% CI)"),
                   yaxis = list(title = "", categoryorder = "array", categoryarray = co$label, rangemode = NULL),
                   shapes = list(list(type = "line", x0 = 1, x1 = 1, yref = "paper", y0 = 0, y1 = 1, line = list(color = RP_COL$muted, dash = "dot"))),
                   margin = list(l = 230))
}

ch_variability <- function(v) {
  if (!NROW(v)) return(rp_empty_plot())
  plotly::plot_ly(v, x = ~mean_latent, y = ~cv, type = "scatter", mode = "markers",
                  marker = list(size = ~pmax(6, 40 * unmet_share + 6), color = ~unmet_share,
                                colorscale = list(c(0, RP_COL$sage), c(0.5, "#E9B7A8"), c(1, RP_COL$stockout)), showscale = TRUE,
                                colorbar = list(title = list(text = "Unmet share"), tickformat = ".0%", thickness = 10),
                                line = list(color = "#ffffff", width = 0.5)),
                  text = ~paste0("P", product_id), hovertemplate = "%{text}<br>mean %{x:.2f} · CV %{y:.2f}<extra></extra>") |>
    rp_plotly_layout(xtitle = "Mean estimated daily demand (normalised units)", ytitle = "Coefficient of variation", legend = FALSE, hovermode = "closest")
}



# Overview: category performance (recorded vs unmet) with stockout-hour rate in hover
ch_categories <- function(cp, source = "cat") {
  if (!NROW(cp)) return(rp_empty_plot())
  cp <- cp[order(cp$latent), ]
  lab <- cp$category
  plotly::plot_ly(source = source) |>
    plotly::add_bars(y = lab, x = cp$observed, name = "Recorded sales", orientation = "h", marker = list(color = RP_COL$forest2),
                     text = sprintf("%d products · stockout-hour rate %.0f%%", cp$products, 100 * cp$so_rate), textposition = "none",
                     hovertemplate = "%{y}<br>recorded %{x:.1f}<br>%{text}<extra></extra>") |>
    plotly::add_bars(y = lab, x = cp$latent - cp$observed, name = "Estimated unmet demand", orientation = "h",
                     marker = list(color = RP_COL$stockout_lt, line = list(color = RP_COL$red, width = 1)),
                     text = sprintf("%.0f%% of estimated demand unmet", 100 * cp$unmet_share), textposition = "none",
                     hovertemplate = "%{y}<br>unmet %{x:.1f}<br>%{text}<extra></extra>") |>
    rp_plotly_layout(xtitle = "Normalised units in period", hovermode = "closest") |>
    plotly::layout(barmode = "stack", yaxis = list(categoryorder = "array", categoryarray = lab, rangemode = NULL, title = ""),
                   margin = list(l = 96, r = 12, t = 8, b = 40), legend = list(orientation = "h", x = 0, y = -0.18)) |>
    plotly::event_register("plotly_click")
}
