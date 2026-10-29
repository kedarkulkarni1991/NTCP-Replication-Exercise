## ---------------------------------------------------------------------------
## Build the file handed to students for the replication exercise.
##
##   Rscript code/06_student_file.R
##
## Students get a cleaned, merged file so that the class can be about the
## difference-in-differences rather than about NSS district codes.  Derived
## variables they are asked to construct -- log sticks per person, log mpce --
## are deliberately left out.
## ---------------------------------------------------------------------------

dat <- readRDS("data/analysis.rds")

KEEP <- c("hhid", "round", "year", "period", "t2", "t3", "ntcp",
          "state_code", "dist_code", "urban", "hh_size", "mpce",
          "wealth_q", "wgt", "bidi_sticks", "cig_sticks",
          "any_bidi", "any_cig")

out <- dat[, KEEP]
out$year <- factor(out$year, levels = c("1999-2000", "2004-05", "2011-12"))
out <- out[order(out$round, out$state_code, out$dist_code, out$hhid), ]
rownames(out) <- NULL

## The exercise asks students to work out that these are repeated cross
## sections, not a panel.  That question only works if hhid is genuinely
## unique, so check rather than assume.
stopifnot(!anyDuplicated(out$hhid))

saveRDS(out, "exercise/ntcp.rds")
write.csv(out, "exercise/ntcp.csv", row.names = FALSE)

cat(sprintf("wrote exercise/ntcp.rds and .csv: %s rows, %d variables\n",
            format(nrow(out), big.mark = ","), ncol(out)))
print(table(round = out$round, ntcp = out$ntcp))
