## ---------------------------------------------------------------------------
## The difference-in-differences, following Nazar et al. (2020).
##
##   Rscript code/04_did.R
##
## The paper uses a two-part model, because the quantity consumed is zero for
## most households and right-skewed among the rest:
##
##   part 1  logit, whether the household consumes at all
##   part 2  linear, log sticks per person, among consuming households
##
## Both parts carry the same DiD structure, with 1999-2000 as the base period:
##
##   y = b0 + b1 NTCP + b2 t2 + b3 t3 + DID1 (NTCP x t2) + DID2 (NTCP x t3) + X
##
##   DID1  NTCP districts against controls, 2004-05 versus 1999-2000.  Both are
##         before the programme, so this is the test of parallel trends.  The
##         paper treats a significant DID1 as a violation.
##   DID2  the same comparison for 2011-12, after the programme.  This is the
##         estimate of interest.
## ---------------------------------------------------------------------------

suppressMessages({library(sandwich); library(lmtest)})
options(width = 100)

dat <- readRDS("data/analysis.rds")
dat$cluster <- paste(dat$state_code, dat$dist_code)

cat(sprintf("households: %s   NTCP districts: 21   control districts: %s\n\n",
            format(nrow(dat), big.mark = ","),
            format(length(unique(dat$cluster[dat$ntcp == 0])), big.mark = ",")))

CTRL <- "+ urban + log(hh_size) + factor(wealth_q) + factor(state_code)"

fit_part1 <- function(y) {
  f <- as.formula(paste0(y, " ~ ntcp + t2 + t3 + ntcp:t2 + ntcp:t3 ", CTRL))
  m <- glm(f, data = dat, family = binomial())
  list(m = m, ct = coeftest(m, vcov = vcovCL(m, cluster = dat$cluster)))
}

fit_part2 <- function(y, flag) {
  s <- dat[dat[[flag]] == 1, ]
  f <- as.formula(paste0(y, " ~ ntcp + t2 + t3 + ntcp:t2 + ntcp:t3 ", CTRL))
  m <- lm(f, data = s)
  list(m = m, ct = coeftest(m, vcov = vcovCL(m, cluster = s$cluster)))
}

show <- function(tag, res, exponentiate = FALSE) {
  ct <- res$ct
  rows <- c("ntcp:t2", "ntcp:t3")
  cat("---", tag, "---\n")
  for (r in rows) {
    e <- ct[r, 1]; se <- ct[r, 2]; p <- ct[r, 4]
    lo <- e - 1.96 * se; hi <- e + 1.96 * se
    if (exponentiate) {
      cat(sprintf("  %-9s OR %6.3f  95%% CI [%6.3f, %6.3f]  p = %.3f\n",
                  ifelse(r == "ntcp:t2", "DID1", "DID2"),
                  exp(e), exp(lo), exp(hi), p))
    } else {
      cat(sprintf("  %-9s    %6.3f  95%% CI [%6.3f, %6.3f]  p = %.3f\n",
                  ifelse(r == "ntcp:t2", "DID1", "DID2"), e, lo, hi, p))
    }
  }
  cat(sprintf("  n = %s\n\n", format(nobs(res$m), big.mark = ",")))
}

cat("=== PART 1: any consumption in the household (odds ratios) ===\n\n")
show("bidi",       fit_part1("any_bidi"), exponentiate = TRUE)
show("cigarettes", fit_part1("any_cig"),  exponentiate = TRUE)

cat("=== PART 2: log sticks per person, among consuming households ===\n\n")
show("bidi",       fit_part2("lbidi_pp", "any_bidi"))
show("cigarettes", fit_part2("lcig_pp",  "any_cig"))

cat("DID1 tests parallel trends: both periods precede the programme, so a\n")
cat("coefficient far from zero (OR far from 1) means the groups were already\n")
cat("diverging and the design is in trouble before the NTCP is reached.\n")
