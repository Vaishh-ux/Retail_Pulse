# Decision-support engine -----------------------------------------------------------
# Converts validated analytical outputs into recommendations. These are
# transparent RULES with documented thresholds (defaults below); they are design
# choices, not scientifically proven decision boundaries. No order quantities,
# dates or money values are produced: the dataset has no inventory, lead-time or
# cost data, and sales are normalised.

RP_RULE_DEFAULTS <- list(
  stockout_days_thr = 3,     # days in the last 7 with a risk event (>= 4 stockout hours)
  lost_share_thr = 0.10,     # estimated unmet share of demand in the last 7 days
  risk_thr = NULL,           # defaults to the risk model's chosen threshold
  surge_ratio = 1.25,        # forecast next 7 days vs estimated demand last 7 days
  decline_ratio = 0.80,
  wape_low_reliability = 0.45,
  min_instock_days = 20,
  w_lost = 1, w_risk = 1, w_anomaly = 1   # priority weights (adjustable in the app)
)

# One row per product with every indicator the rules use
rp_product_indicators <- function(d, fc_next, chosen, anomalies, risk_next, cv_product, per_product, growth = 1) {
  last_dt <- max(d$dt)
  recent <- d |>
    dplyr::filter(dt > last_dt - 7) |>
    dplyr::group_by(product_id) |>
    dplyr::summarise(obs7 = sum(sale_amount), latent7 = sum(latent), stockout_days7 = sum(event, na.rm = TRUE),
                     .groups = "drop") |>
    dplyr::mutate(lost_share7 = ifelse(latent7 > 0, (latent7 - obs7) / latent7, 0))
  f7 <- fc_next |>
    dplyr::filter(.model == chosen) |>
    dplyr::group_by(product_id) |>
    dplyr::slice_head(n = 7) |>
    dplyr::summarise(fc7 = sum(mean) * growth, .groups = "drop")
  an <- if (NROW(anomalies)) anomalies |>
    dplyr::filter(dt > last_dt - 7) |>
    dplyr::group_by(product_id) |>
    dplyr::summarise(unexplained_drops7 = sum(cause == "Unexplained" & direction == "drop"),
                     unexplained_surges7 = sum(cause == "Unexplained" & direction == "surge"),
                     last_anomaly = max(dt), .groups = "drop") else
    tibble::tibble(product_id = integer(), unexplained_drops7 = integer(), unexplained_surges7 = integer(), last_anomaly = as.Date(character()))
  rel <- cv_product |>
    dplyr::filter(.model == chosen) |>
    dplyr::select(product_id, cv_wape = WAPE)
  recent |>
    dplyr::left_join(f7, by = "product_id") |>
    dplyr::left_join(an, by = "product_id") |>
    dplyr::left_join(risk_next[, c("product_id", "risk")], by = "product_id") |>
    dplyr::left_join(rel, by = "product_id") |>
    dplyr::left_join(per_product[, c("product_id", "full_instock_days", "zero_sale_share")], by = "product_id") |>
    dplyr::mutate(dplyr::across(c(unexplained_drops7, unexplained_surges7), ~ tidyr::replace_na(.x, 0L)),
                  fc_ratio = ifelse(latent7 > 0, fc7 / latent7, NA_real_))
}

rp_reliability <- function(cv_wape, instock_days, zero_share, p) {
  dplyr::case_when(
    is.na(cv_wape) | instock_days < p$min_instock_days | zero_share > 0.5 ~ "Low",
    cv_wape > p$wape_low_reliability ~ "Low",
    cv_wape > 0.30 ~ "Medium",
    TRUE ~ "High")
}

rp_recommend <- function(ind, params = list(), risk_threshold = 0.5) {
  p <- utils::modifyList(RP_RULE_DEFAULTS, params)
  p$risk_thr <- p$risk_thr %||% risk_threshold
  ind$reliability <- rp_reliability(ind$cv_wape, ind$full_instock_days, ind$zero_sale_share, p)
  # accumulate plain vectors and build one table at the end (building a tibble per
  # recommendation made this function ~10x slower)
  acc <- list(product_id = integer(), action = character(), reason = character(), evidence = character(),
              urgency = character(), reliability = character(), rule = character())
  add <- function(i, action, reason, evidence, urgency, rule) {
    acc$product_id <<- c(acc$product_id, ind$product_id[i]); acc$action <<- c(acc$action, action)
    acc$reason <<- c(acc$reason, reason); acc$evidence <<- c(acc$evidence, evidence)
    acc$urgency <<- c(acc$urgency, urgency); acc$reliability <<- c(acc$reliability, ind$reliability[i])
    acc$rule <<- c(acc$rule, rule)
  }
  for (i in seq_len(nrow(ind))) {
    r <- ind[i, ]
    fired <- FALSE
    if (r$stockout_days7 >= p$stockout_days_thr || (!is.na(r$risk) && r$risk >= p$risk_thr && r$lost_share7 >= p$lost_share_thr)) {
      urg <- if (r$lost_share7 >= 0.2 || r$stockout_days7 >= 4) "High" else "Medium"
      add(i, "Consider replenishing earlier",
          sprintf("Out of stock for 4+ trading hours on %d of the last 7 days; about %.0f%% of estimated demand went unmet.",
                  r$stockout_days7, 100 * r$lost_share7),
          sprintf("Stockout days (7d) = %d; unmet share = %.1f%%; next-day stockout risk = %s",
                  r$stockout_days7, 100 * r$lost_share7, if (is.na(r$risk)) "n/a" else sprintf("%.0f%%", 100 * r$risk)),
          urg, sprintf("R1: stockout days >= %g OR (risk >= %.2f AND unmet share >= %.0f%%)", p$stockout_days_thr, p$risk_thr, 100 * p$lost_share_thr))
      fired <- TRUE
    }
    if (r$unexplained_drops7 > 0) {
      add(i, "Investigate unexplained sales drop",
          "Sales fell far below this product's normal level with no stockout, promotion, holiday or heavy rain recorded.",
          sprintf("%d unexplained drop(s) in the last 7 days (robust z <= -threshold)", r$unexplained_drops7),
          "Medium", "R2: unexplained drop anomaly in the last 7 days")
      fired <- TRUE
    }
    if ((!is.na(r$fc_ratio) && r$fc_ratio >= p$surge_ratio) || r$unexplained_surges7 > 0) {
      by_fc <- !is.na(r$fc_ratio) && r$fc_ratio >= p$surge_ratio
      why <- c(if (by_fc) sprintf("Forecast for the next 7 days is %.0f%% of estimated demand in the last 7 days.", 100 * r$fc_ratio),
               if (r$unexplained_surges7 > 0) sprintf("Sales were far above normal on %d recent day(s) with no promotion or holiday recorded.", r$unexplained_surges7))
      add(i, "Review possible demand surge", paste(why, collapse = " "),
          sprintf("Forecast ratio = %.2f; unexplained surges (7d) = %d", r$fc_ratio, r$unexplained_surges7),
          if (r$reliability == "Low") "Low" else "Medium", sprintf("R3: forecast ratio >= %.2f OR unexplained surge", p$surge_ratio))
      fired <- TRUE
    }
    if (!is.na(r$fc_ratio) && r$fc_ratio <= p$decline_ratio && r$reliability != "Low") {
      add(i, "Plan for lower demand",
          sprintf("Forecast for the next 7 days is %.0f%% of estimated demand in the last 7 days.", 100 * r$fc_ratio),
          sprintf("Forecast ratio = %.2f (reliability %s)", r$fc_ratio, r$reliability),
          "Low", sprintf("R4: forecast ratio <= %.2f and reliability not Low", p$decline_ratio))
      fired <- TRUE
    }
    if (r$reliability == "Low") {
      add(i, "Use caution: forecast unreliable",
          "Too little in-stock history or high past forecast error; rely on judgement for this product.",
          sprintf("CV WAPE = %s; in-stock days = %d; zero-sale share = %.0f%%",
                  if (is.na(r$cv_wape)) "n/a" else sprintf("%.2f", r$cv_wape), r$full_instock_days, 100 * r$zero_sale_share),
          "Info", "R5: reliability = Low")
      fired <- TRUE
    }
    if (!fired) add(i, "Maintain current approach", "No rule triggered; demand and availability are within normal ranges.",
                    sprintf("Unmet share = %.1f%%; forecast ratio = %s", 100 * r$lost_share7, if (is.na(r$fc_ratio)) "n/a" else sprintf("%.2f", r$fc_ratio)),
                    "Low", "R6: no other rule fired")
  }
  out <- tibble::as_tibble(acc) |> dplyr::left_join(ind, by = "product_id", suffix = c("", ".ind"))
  urg_w <- c(High = 3, Medium = 2, Low = 1, Info = 0.5)
  out$priority <- round(urg_w[out$urgency] * (1 + p$w_lost * out$lost_share7 + p$w_risk * tidyr::replace_na(out$risk, 0) +
                                                p$w_anomaly * pmin(1, out$unexplained_drops7 + out$unexplained_surges7)), 3)
  out <- out[order(-out$priority, seq_len(nrow(out))), ]
  out$if_ignored <- dplyr::case_when(
    out$action == "Consider replenishing earlier" ~ sprintf("At the recent rate, about %.0f%% of this product's demand may keep going unmet.", 100 * out$lost_share7),
    out$action == "Investigate unexplained sales drop" ~ "If the cause is a quality, price or display problem, it may persist unnoticed.",
    out$action == "Review possible demand surge" ~ "If the rise is real, stock may run out sooner than usual.",
    TRUE ~ "")
  out$recommendation_type <- ifelse(out$rule %in% c("R5: reliability = Low", "R6: no other rule fired") | grepl("^R6", out$rule),
                                    "General operational suggestion", "Data-supported")
  out
}
