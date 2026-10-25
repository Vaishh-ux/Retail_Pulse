# Scenario support: association between promotion depth and demand ---------------
# Per first-level category, on in-stock training days:
#   log(latent + 0.1) ~ promo_depth + weekday + product + holiday + precipitation
# The promo_depth coefficient is an OBSERVATIONAL association, not a causal
# effect: promotions are not randomly assigned.

rp_promo_effects <- function(d) {
  x <- d[d$split == "train" & d$any_stockout == 0L, ]
  x$y <- log(x$latent + 0.1)
  res <- lapply(split(x, x$first_category_id), function(g) {
    n_promo <- sum(g$promo_depth > 0)
    if (n_promo < 10 || length(unique(g$product_id)) < 2) {
      return(tibble::tibble(first_category_id = g$first_category_id[1], n_days = nrow(g), n_promo_days = n_promo,
                            beta = NA_real_, se = NA_real_, note = "Too few promotion days for a reliable estimate"))
    }
    m <- stats::lm(y ~ promo_depth + factor(weekday) + factor(product_id) + holiday_flag + precpt, data = g)
    co <- summary(m)$coefficients["promo_depth", ]
    tibble::tibble(first_category_id = g$first_category_id[1], n_days = nrow(g), n_promo_days = n_promo,
                   beta = co[["Estimate"]], se = co[["Std. Error"]], note = "Observational association")
  })
  out <- dplyr::bind_rows(res)
  out$lift_10pp <- exp(0.1 * out$beta) - 1
  out$lift_10pp_lo <- exp(0.1 * (out$beta - 1.96 * out$se)) - 1
  out$lift_10pp_hi <- exp(0.1 * (out$beta + 1.96 * out$se)) - 1
  out
}

# Multiplier on demand for a hypothetical discount depth (0-0.5) with a 95% CI
rp_promo_multiplier <- function(beta, se, depth) {
  c(mid = exp(beta * depth), lo = exp((beta - 1.96 * se) * depth), hi = exp((beta + 1.96 * se) * depth))
}
