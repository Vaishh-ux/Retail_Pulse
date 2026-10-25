# Stockout-aware (latent) demand estimation ------------------------------------
# Method: each product has an hourly demand profile (share of the day's sales in
# each hour), estimated on fully in-stock days separately for weekdays and
# weekends and shrunk towards the product's overall profile. On a day with
# out-of-stock trading hours, the day's demand level is inferred from the sales
# in the hours that were in stock, and the missing hours are filled with
# level x profile share. Assumption: the hourly shape of demand is stable.

rp_share_matrix <- function(H, rows) {
  tot <- rowSums(H[rows, , drop = FALSE])
  sweep(H[rows, , drop = FALSE], 1, tot, "/")
}

# Returns a list: profile lookup function + raw sums for leave-one-out use
rp_fit_profiles <- function(d, H, k_shrink = 5) {
  full <- which(d$full_instock == 1L)
  sh <- rp_share_matrix(H, full)
  key_g <- paste(d$product_id[full], d$weektype[full])
  key_p <- as.character(d$product_id[full])
  sum_g <- rowsum(sh, key_g); n_g <- as.vector(table(key_g)[rownames(sum_g)])
  sum_p <- rowsum(sh, key_p); n_p <- as.vector(table(key_p)[rownames(sum_p)])
  store_prof <- colMeans(sh)
  list(sum_g = sum_g, n_g = setNames(n_g, rownames(sum_g)),
       sum_p = sum_p, n_p = setNames(n_p, rownames(sum_p)),
       store = store_prof, k = k_shrink)
}

# profile for one product/weektype; `exclude` = share vector of a day to leave out
rp_profile <- function(pf, product, weektype, exclude = NULL) {
  kp <- as.character(product); kg <- paste(product, weektype)
  sp <- if (kp %in% rownames(pf$sum_p)) pf$sum_p[kp, ] else pf$store * 0
  np <- if (kp %in% names(pf$n_p)) pf$n_p[[kp]] else 0
  sg <- if (kg %in% rownames(pf$sum_g)) pf$sum_g[kg, ] else pf$store * 0
  ng <- if (kg %in% names(pf$n_g)) pf$n_g[[kg]] else 0
  if (!is.null(exclude)) { sp <- sp - exclude; np <- np - 1; sg <- sg - exclude; ng <- ng - 1 }
  prod_prof <- if (np > 0) (sp + pf$k * pf$store) / (np + pf$k) else pf$store
  prof <- if (ng > 0) (sg + pf$k * prod_prof) / (ng + pf$k) else prod_prof
  prof / sum(prof)
}

# Estimate latent demand for every product-day
rp_latent_demand <- function(d, H, S, cfg, pf) {
  n <- nrow(d)
  latent <- d$sale_amount; method <- rep("observed", n); share_in <- rep(1, n)
  tr <- cfg$trading_idx
  # leakage-free fallback level: trailing median of the same product's fully
  # in-stock days over the previous 28 days (computed on observed sales)
  fb <- d |>
    dplyr::group_by(product_id) |>
    dplyr::mutate(fb = slider::slide_dbl(ifelse(full_instock == 1L, sale_amount, NA_real_),
                                         function(x) if (all(is.na(x))) NA_real_ else stats::median(x, na.rm = TRUE),
                                         .before = cfg$baseline_window, .after = -1)) |>
    dplyr::ungroup()
  fallback <- fb$fb
  prod_med <- tapply(d$sale_amount[d$full_instock == 1L], d$product_id[d$full_instock == 1L], stats::median)
  cache <- new.env()
  for (i in which(d$stock_h > 0)) {
    key <- paste(d$product_id[i], d$weektype[i])
    prof <- cache[[key]]
    if (is.null(prof)) { prof <- rp_profile(pf, d$product_id[i], d$weektype[i]); cache[[key]] <- prof }
    out <- tr[S[i, tr] == 1]
    s_in <- 1 - sum(prof[out])
    share_in[i] <- s_in
    obs_in <- sum(H[i, -out])
    if (s_in >= cfg$min_share_in) {
      level <- obs_in / s_in; method[i] <- "profile"
    } else {
      level <- fallback[i]
      if (is.na(level)) level <- prod_med[as.character(d$product_id[i])]
      if (is.na(level)) level <- obs_in / max(s_in, 0.05)
      method[i] <- "fallback"
    }
    fill <- pmax(0, level * prof[out] - H[i, out])
    latent[i] <- d$sale_amount[i] + sum(fill)
  }
  d$latent <- round(latent, 4)
  d$latent_method <- method
  d$share_in_stock <- round(share_in, 4)
  d$lost <- round(d$latent - d$sale_amount, 4)
  d
}

# Validation: on fully in-stock days, hide all trading hours from a random
# cut-off hour onwards (a simulated stockout), estimate the day total from the
# remaining hours with a leave-one-out profile, and compare with the truth.
rp_validate_latent <- function(d, H, cfg, pf, seed = 1) {
  set.seed(seed)
  cand <- which(d$full_instock == 1L & d$sale_amount >= 0.5 & rowSums(H > 0) >= 3)
  res <- vector("list", length(cand))
  for (j in seq_along(cand)) {
    i <- cand[j]
    cut0 <- sample(12:20, 1)                       # 0-based hour where the "stockout" starts
    hide <- (cut0 + 1):22                           # 1-based positions for hours cut0..21
    sh_day <- H[i, ] / sum(H[i, ])
    prof <- rp_profile(pf, d$product_id[i], d$weektype[i], exclude = sh_day)
    s_in <- 1 - sum(prof[hide])
    obs_in <- sum(H[i, -hide])
    est <- if (s_in >= cfg$min_share_in) obs_in / s_in else NA_real_
    res[[j]] <- data.frame(product_id = d$product_id[i], dt = d$dt[i], cutoff_hour = cut0,
                           actual = d$sale_amount[i], observed_only = obs_in, estimate = est,
                           hidden_share_true = sum(sh_day[hide]), hidden_share_prof = sum(prof[hide]))
  }
  v <- dplyr::bind_rows(res)
  v <- v[!is.na(v$estimate), ]
  m <- function(pred, act) c(MAE = mean(abs(pred - act)), WAPE = sum(abs(pred - act)) / sum(act),
                             bias = sum(pred - act) / sum(act))
  list(rows = v,
       metrics = rbind(profile_method = m(v$estimate, v$actual),
                       observed_only = m(v$observed_only, v$actual)),
       by_cutoff = v |>
         dplyr::group_by(cutoff_hour) |>
         dplyr::summarise(n = dplyr::n(),
                          wape_profile = sum(abs(estimate - actual)) / sum(actual),
                          wape_observed = sum(abs(observed_only - actual)) / sum(actual), .groups = "drop"))
}
