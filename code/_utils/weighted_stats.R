# weighted_stats -- shared weighted quantile and population-count helpers
# Author - Ben Glasner
# research title - EIG Wage Figure Explain Everything
# research question - how have real hourly wages evolved across percentiles, age bins, and generations from 1982 through present?

# Sourced once at the end of code/_utils/00_packages.R, which every
# analysis script loads. Defining these here guarantees that every
# reporting path (figures A-E, the generation/cohort panels, the per-year
# summary in 02a, the EPI spot-check gate in 10, and the binding-minimum
# shares in 20e) uses ONE implementation of each statistic instead of
# parallel inline copies that can silently drift apart.
#
# Two functions:
#
#   weighted_quantile(x, w, p)
#     EARNWT-weighted quantile using the Stata `_pctile` / EPI State of
#     Working America no-interpolation ("lower") convention: sort x
#     ascending, cumulate the weights, and return the smallest x whose
#     cumulative weight reaches p * total weight. The returned value is
#     always an observed value of x -- no interpolation between adjacent
#     observations. This matches the construction the project validates
#     against in 10_epi_spot_checks.R and replaces the interpolating
#     matrixStats::weightedMedian() previously used in figures B/C/E and
#     the generation panel (02b).
#
#   weighted_population(w, year, month)
#     Average monthly population represented by a pooled set of CPS-ORG
#     person-month records: sum(w) divided by the number of distinct
#     survey months (year * 12 + month) present. Each month's EARNWT sums
#     to the full population for that month, so pooling M survey months
#     without dividing inflates a population count by a factor of M. The
#     divisor is computed per call from the rows actually present, so it
#     is correct for a single-month cell (divisor 1), a full calendar year
#     (12), a partial year such as the current year (whatever is observed),
#     and multi-year pools (figures C and E).

###################################
###   Weighted quantile         ###
###################################
# x  numeric vector of values (e.g., real hourly wage)
# w  numeric vector of weights (EARNWT), same length as x
# p  numeric scalar or vector of probabilities in [0, 1]
#
# Rows with NA x, NA w, or non-positive w are dropped before sorting.
# Returns a numeric vector the same length as p (NA_real_ for each p when
# no valid rows remain).
weighted_quantile <- function(x, w, p) {
  if (length(x) != length(w)) {
    stop("weighted_quantile() -- x and w must have equal length.")
  }

  keep_bool <- !is.na(x) & !is.na(w) & w > 0
  x <- x[keep_bool]
  w <- w[keep_bool]

  if (length(x) == 0L) {
    return(rep(NA_real_, length(p)))
  }

  ord_int    <- order(x)
  x_ord_num  <- x[ord_int]
  cum_wt_num <- cumsum(w[ord_int])
  total_num  <- cum_wt_num[length(cum_wt_num)]

  vapply(
    p,
    function(prob_num) {
      hit_idx_int <- which(cum_wt_num >= prob_num * total_num)[1]
      x_ord_num[hit_idx_int]
    },
    numeric(1L)
  )
}

###################################
###   Weighted population count ###
###################################
# w      numeric vector of weights (EARNWT)
# year   integer/numeric vector of survey years, same length as w
# month  integer/numeric vector of survey months (1-12), same length as w
#
# Returns the weighted population averaged over the distinct survey months
# present (sum(w) / n_distinct(year * 12 + month)). Rows with NA/non-positive
# weight or NA year/month are excluded from both the sum and the month count.
# Returns NA_real_ when no valid rows remain.
weighted_population <- function(w, year, month) {
  if (length(w) != length(year) || length(w) != length(month)) {
    stop("weighted_population() -- w, year, and month must have equal length.")
  }

  keep_bool <- !is.na(w) & w > 0 & !is.na(year) & !is.na(month)

  if (!any(keep_bool)) {
    return(NA_real_)
  }

  period_key_int <- as.integer(year[keep_bool]) * 12L + as.integer(month[keep_bool])
  n_periods_int  <- length(unique(period_key_int))

  sum(w[keep_bool]) / n_periods_int
}
