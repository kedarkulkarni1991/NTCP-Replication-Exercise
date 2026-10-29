## ---------------------------------------------------------------------------
## Extract household bidi and cigarette consumption from NSS Block 5.
##
##   Rscript code/02_extract_tobacco.R
##
## Block 5 is the item-level block, "monthly consumption of food, pan, tobacco
## and intoxicants".  Bidi and cigarettes are recorded there as a count of
## sticks, which is the outcome the paper uses.
##
## The item codes are NOT the same across rounds.  Rounds 55 and 61 use the
## pre-2011 layout, where tobacco runs 320-327; round 68 uses 310-317.  Reading
## round 68 with 320/321 would silently return ganja and toddy instead.
##
##   round 55, 61 : 320 = bidi (no.)   321 = cigarettes (no.)
##   round 68     : 310 = bidi (no.)   311 = cigarettes (no.)
##
## Verified against Schedule_55_1.pdf and Schedule_68_1.pdf, and for round 61
## from the data itself (codes 326/327 carry observations, which is impossible
## under the round-68 layout).
## ---------------------------------------------------------------------------

suppressMessages({library(haven)})

ROOT <- "."



HOME     <- path.expand("~")
ONEDRIVE <- file.path(HOME, "Library/CloudStorage/OneDrive-AzimPremjiFoundation")
NSSDATA  <- file.path(ONEDRIVE, "NSS Consumption Datasets")

z <- function(x) suppressWarnings(as.numeric(haven::zap_labels(x)))

## Round 55's household key, built the same way on both sides of the merge.
pad <- function(x, w) formatC(as.character(haven::zap_labels(x)), width = w, flag = "0")
r55_key <- function(state, stratum, hhid)
  paste0(pad(state, 2), pad(stratum, 2), pad(hhid, 11))

CODES <- list("55" = c(bidi = 320, cig = 321),
              "61" = c(bidi = 320, cig = 321),
              "68" = c(bidi = 310, cig = 311))

## ---- per-round readers -----------------------------------------------------
read_block5 <- function(rnd) {
  if (rnd == 55) {
    f <- file.path(NSSDATA, "NSS 55th round",
                   "Household Consumer Expenditure, July 1999 - June 2000_Spss",
                   "Block 5_Monthly household expenditure on food and non-food items.sav")
    d <- read_sav(f, col_select = c("State", "Stratum", "HHID",
                                    "B5_q1", "B5_q5", "B5_q6"))
    ## This file has BOTH an "ID" column, which is the constant "W3" and is not
    ## a key, and an "HHID" column, which is one.  Use HHID.
    ##
    ## Do not be tempted to rebuild the key from Vill_Blk_Slno + SubRound +
    ## SubSample + Stage2_Stratum + Hhold_no instead.  It looks equivalent --
    ## HHID is exactly those five fields concatenated -- but the SubSample
    ## column disagrees with the 7th digit of HHID in both this file and the
    ## interim household file, so the reconstruction collapses pairs of
    ## genuinely different households onto one key.  That silently merged
    ## 19,122 round-55 households 2:1 and credited each with its twin's
    ## tobacco.  State and stratum are still prefixed because HHID is not
    ## unique nationally.
    key <- r55_key(d$State, d$Stratum, d$HHID)
    ## B5_q5 is the 30-day quantity.  Round 55 ran the experimental dual-recall
    ## design, so a 7-day column (B5_q3) also exists; the paper's outcome is
    ## monthly, so the 30-day column is the right one.
    data.frame(hhid = key, item = z(d$B5_q1),
               qty = z(d$B5_q5), val = z(d$B5_q6))

  } else if (rnd == 61) {
    f <- list.files(file.path(HOME, "nss_ces/r61"), pattern = "^Block 5_",
                    recursive = TRUE, full.names = TRUE)[1]
    d <- read_dta(f, col_select = c("HHID", "B5_q1", "B5_q5", "B5_q6"))
    data.frame(hhid = as.character(d$HHID), item = z(d$B5_q1),
               qty = z(d$B5_q5), val = z(d$B5_q6))

  } else {
    f <- file.path(HOME, "nss_ces/r68/data/STATA_data_nss68_consumer_expenditure_type2",
                   "Block5_1_5_2_6_ Level 5.dta")
    d <- read_dta(f, col_select = c("HHID", "Item_Code",
                                    "Total_Consumption_Quantity",
                                    "Total_Consumption_Value"))
    data.frame(hhid = as.character(d$HHID), item = z(d$Item_Code),
               qty = z(d$Total_Consumption_Quantity),
               val = z(d$Total_Consumption_Value))
  }
}

## ---- collapse one round to the household -----------------------------------
tobacco_for <- function(rnd) {
  cd <- CODES[[as.character(rnd)]]
  b5 <- read_block5(rnd)
  message(sprintf("  round %d: %s item rows", rnd, format(nrow(b5), big.mark = ",")))

  keep <- subset(b5, item %in% cd)
  keep$qty[is.na(keep$qty)] <- 0
  keep$val[is.na(keep$val)] <- 0

  agg <- function(code) {
    s <- subset(keep, item == code)
    stats::aggregate(cbind(qty, val) ~ hhid, data = s, FUN = sum)
  }
  bd <- agg(cd["bidi"]); names(bd) <- c("hhid", "bidi_sticks", "bidi_rs")
  cg <- agg(cd["cig"]);  names(cg) <- c("hhid", "cig_sticks",  "cig_rs")

  out <- merge(bd, cg, by = "hhid", all = TRUE)
  for (v in setdiff(names(out), "hhid")) out[[v]][is.na(out[[v]])] <- 0
  out$round <- rnd

  message(sprintf("     households reporting bidi %s, cigarettes %s",
                  format(sum(out$bidi_sticks > 0), big.mark = ","),
                  format(sum(out$cig_sticks  > 0), big.mark = ",")))
  message(sprintf("     mean sticks among consumers: bidi %.0f (Rs %.2f each), cig %.0f (Rs %.2f each)",
                  mean(out$bidi_sticks[out$bidi_sticks > 0]),
                  sum(out$bidi_rs[out$bidi_sticks > 0]) / sum(out$bidi_sticks[out$bidi_sticks > 0]),
                  mean(out$cig_sticks[out$cig_sticks > 0]),
                  sum(out$cig_rs[out$cig_sticks > 0]) / sum(out$cig_sticks[out$cig_sticks > 0])))
  out
}

message("extracting Block 5 tobacco items")
tob <- do.call(rbind, lapply(c(55, 61, 68), tobacco_for))

saveRDS(tob, file.path(ROOT, "data/tobacco_by_household.rds"))
message(sprintf("\nwrote data/tobacco_by_household.rds (%s rows)",
                format(nrow(tob), big.mark = ",")))
