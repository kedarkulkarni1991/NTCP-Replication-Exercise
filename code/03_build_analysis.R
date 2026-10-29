## ---------------------------------------------------------------------------
## Assemble the analysis file: tobacco consumption + household characteristics
## + the NTCP treatment flag, stacked across the three rounds.
##
##   Rscript code/03_build_analysis.R
## ---------------------------------------------------------------------------

suppressMessages({library(haven)})

INTERIM <- "../nss-consumption-panel/data/interim"
z <- function(x) suppressWarnings(as.numeric(haven::zap_labels(x)))

## Survey period of each round, and its position relative to the NTCP, which
## was rolled out across 2007-2009.
ROUNDS <- data.frame(
  round  = c(55, 61, 68),
  year   = c("1999-2000", "2004-05", "2011-12"),
  period = c("pre", "pre2", "post"),
  t2     = c(0, 1, 0),      # second pre-period, for the parallel-trend test
  t3     = c(0, 0, 1))      # post-NTCP

tob <- readRDS("data/tobacco_by_household.rds")
trt <- read.csv("data/treatment_districts.csv")

## Round 55's key is state + stratum + HHID, to match 02_extract_tobacco.R;
## see the note there for why HHID and not its component fields.
pad <- function(x, w) formatC(as.character(haven::zap_labels(x)), width = w, flag = "0")

build_round <- function(rnd) {
  hh <- read_dta(file.path(INTERIM, sprintf("r%d_hh.dta", rnd)))
  key <- if (rnd == 55)
    paste0(pad(hh$state_code, 2), pad(hh$Stratum, 2), pad(hh$HHID, 11))
  else as.character(hh$HHID)

  stopifnot(!anyDuplicated(key))

  d <- data.frame(
    round      = rnd,
    hhid       = key,
    state_code = z(hh$state_code),
    dist_code  = z(hh$district_code),
    sector     = z(hh$sector),
    hh_size    = z(hh$hh_size),
    mpce       = z(hh$mpce),
    wgt        = z(hh$wgt))

  ## tobacco: households absent from the Block 5 extract reported none
  t <- subset(tob, round == rnd, select = -round)
  d <- merge(d, t, by = "hhid", all.x = TRUE)
  for (v in c("bidi_sticks", "bidi_rs", "cig_sticks", "cig_rs"))
    d[[v]][is.na(d[[v]])] <- 0

  ## treatment: one of the 21 NTCP districts that could be matched in all three
  ## rounds (see 01_build_concordance.py)
  k <- subset(trt, round == rnd)
  d$ntcp <- as.integer(paste(d$state_code, d$dist_code) %in%
                       paste(k$state_code, k$district_code))
  d
}

message("building analysis file")
dat <- do.call(rbind, lapply(ROUNDS$round, build_round))
dat <- merge(dat, ROUNDS, by = "round")

## ---- outcomes --------------------------------------------------------------
## Part 1: did the household consume at all.
dat$any_bidi <- as.integer(dat$bidi_sticks > 0)
dat$any_cig  <- as.integer(dat$cig_sticks  > 0)

## Part 2: sticks per person per month, among consuming households.  Logged,
## as in the paper, because the distribution is heavily right-skewed.
dat$bidi_pp <- dat$bidi_sticks / dat$hh_size
dat$cig_pp  <- dat$cig_sticks  / dat$hh_size
dat$lbidi_pp <- ifelse(dat$any_bidi == 1, log(dat$bidi_pp), NA)
dat$lcig_pp  <- ifelse(dat$any_cig  == 1, log(dat$cig_pp),  NA)

## ---- controls --------------------------------------------------------------
dat$urban <- as.integer(dat$sector == 2)
dat$lmpce <- ifelse(dat$mpce > 0, log(dat$mpce), NA)

## Wealth quintile within round, so that it means the same thing in each round
## despite inflation.
dat$wealth_q <- ave(dat$lmpce, dat$round, FUN = function(x)
  as.integer(cut(x, stats::quantile(x, 0:5/5, na.rm = TRUE),
                 include.lowest = TRUE)))

keep <- !is.na(dat$hh_size) & dat$hh_size >= 1 & !is.na(dat$lmpce) &
        !is.na(dat$state_code) & !is.na(dat$dist_code)
message(sprintf("  dropped %d of %d rows on missing covariates",
                sum(!keep), nrow(dat)))
dat <- dat[keep, ]

dat$period <- factor(dat$period, levels = c("pre", "pre2", "post"))

saveRDS(dat, "data/analysis.rds")

## ---- what we built ---------------------------------------------------------
message("\nhouseholds by round and treatment status")
print(table(round = dat$round, ntcp = dat$ntcp))

message("\nunweighted prevalence, % of households reporting any consumption")
pv <- aggregate(cbind(any_bidi, any_cig) ~ year + ntcp, data = dat,
                FUN = function(x) round(100 * mean(x), 1))
print(pv[order(pv$ntcp, pv$year), ], row.names = FALSE)

message("\nsticks per person per month, among consuming households")
sp <- aggregate(cbind(bidi_pp, cig_pp) ~ year + ntcp,
                data = subset(dat, any_bidi == 1 | any_cig == 1),
                FUN = function(x) round(mean(x), 1))
print(sp[order(sp$ntcp, sp$year), ], row.names = FALSE)

message(sprintf("\nwrote data/analysis.rds (%s rows)", format(nrow(dat), big.mark = ",")))
