## ---------------------------------------------------------------------------
## Worked solutions to the NTCP replication exercise.
## Every block of output in the exercise PDF comes from running this file.
##
##   Rscript solutions.R > solutions_output.txt 2>&1
## ---------------------------------------------------------------------------

options(width = 78, digits = 5, useFancyQuotes = FALSE)
suppressMessages({library(sandwich); library(lmtest); library(ggplot2)})

hdr <- function(x) cat("\n\n##### ", x, " #####\n\n", sep = "")

## ---- Q1 --------------------------------------------------------------------
hdr("Q1 load and describe")
ntcp <- readRDS("ntcp.rds")
dim(ntcp)
table(year = ntcp$year, treated = ntcp$ntcp)

hdr("Q1b districts in each group")
## District codes are NOT comparable across rounds -- the same number means a
## different district in 1999 than in 2011 -- so count within each round.
dcount <- function(d) c(
  treated = length(unique(paste(d$state_code, d$dist_code)[d$ntcp == 1])),
  control = length(unique(paste(d$state_code, d$dist_code)[d$ntcp == 0])))
t(sapply(split(ntcp, ntcp$round), dcount))

## ---- Q2 --------------------------------------------------------------------
hdr("Q2 is this a panel?")
## If households were followed, the same hhid would appear in more than one
## round. Count how many do.
tab <- table(ntcp$hhid)
c(households       = length(tab),
  appearing_twice  = sum(tab > 1),
  rows             = nrow(ntcp))

## ---- Q3 --------------------------------------------------------------------
hdr("Q3 prevalence by year and group, %")
pv <- aggregate(cbind(any_bidi, any_cig) ~ year + ntcp, data = ntcp,
                FUN = function(x) round(100 * mean(x), 1))
pv[order(pv$ntcp, pv$year), ]

## ---- Q4 --------------------------------------------------------------------
hdr("Q4 difference-in-differences by hand, bidi prevalence")
cell <- tapply(ntcp$any_bidi, list(treated = ntcp$ntcp, year = ntcp$year), mean)
round(100 * cell, 2)

chg_t <- cell["1", "2011-12"] - cell["1", "1999-2000"]
chg_c <- cell["0", "2011-12"] - cell["0", "1999-2000"]
round(100 * c(change_treated = chg_t, change_control = chg_c,
              DiD = chg_t - chg_c), 2)

## ---- Q5 --------------------------------------------------------------------
hdr("Q5 the same thing as a regression (linear probability model)")
m5 <- lm(any_bidi ~ ntcp * t3, data = subset(ntcp, year != "2004-05"))
round(coef(summary(m5)), 4)

## ---- Q6 --------------------------------------------------------------------
hdr("Q6 all three rounds, with controls and clustered standard errors")
ntcp$cluster <- paste(ntcp$state_code, ntcp$dist_code)
m6 <- lm(any_bidi ~ ntcp + t2 + t3 + ntcp:t2 + ntcp:t3 +
           urban + log(hh_size) + factor(wealth_q) + factor(state_code),
         data = ntcp)
ct6 <- coeftest(m6, vcov = vcovCL(m6, cluster = ntcp$cluster))
round(ct6[c("ntcp", "t2", "t3", "ntcp:t2", "ntcp:t3"), ], 4)

## ---- Q7 --------------------------------------------------------------------
hdr("Q7 part 1 of the two-part model: logit, odds ratios")
g7 <- glm(any_bidi ~ ntcp + t2 + t3 + ntcp:t2 + ntcp:t3 +
            urban + log(hh_size) + factor(wealth_q) + factor(state_code),
          data = ntcp, family = binomial())
ct7 <- coeftest(g7, vcov = vcovCL(g7, cluster = ntcp$cluster))
or <- function(ct, r) {
  e <- ct[r, 1]; se <- ct[r, 2]
  round(c(OR = exp(e), lo = exp(e - 1.96 * se), hi = exp(e + 1.96 * se),
          p = ct[r, 4]), 3)
}
rbind(DID1 = or(ct7, "ntcp:t2"), DID2 = or(ct7, "ntcp:t3"))

## ---- Q8 --------------------------------------------------------------------
hdr("Q8 part 2: log sticks per person, among consuming households")
cons <- subset(ntcp, any_bidi == 1)
cons$lbidi_pp <- log(cons$bidi_sticks / cons$hh_size)
m8 <- lm(lbidi_pp ~ ntcp + t2 + t3 + ntcp:t2 + ntcp:t3 +
           urban + log(hh_size) + factor(wealth_q) + factor(state_code),
         data = cons)
ct8 <- coeftest(m8, vcov = vcovCL(m8, cluster = cons$cluster))
round(ct8[c("ntcp:t2", "ntcp:t3"), ], 4)
c(n_consuming = nrow(cons))

## ---- Q9 --------------------------------------------------------------------
hdr("Q9 the pre-trend test on its own")
## DID1 compares 2004-05 with 1999-2000. Both precede the programme, so under
## parallel trends it should be zero.
round(or(ct7, "ntcp:t2"), 3)

## ---- Q10 -------------------------------------------------------------------
hdr("Q10 cigarettes, for comparison")
g10 <- glm(any_cig ~ ntcp + t2 + t3 + ntcp:t2 + ntcp:t3 +
             urban + log(hh_size) + factor(wealth_q) + factor(state_code),
           data = ntcp, family = binomial())
ct10 <- coeftest(g10, vcov = vcovCL(g10, cluster = ntcp$cluster))
rbind(DID1 = or(ct10, "ntcp:t2"), DID2 = or(ct10, "ntcp:t3"))

## ---- figure ----------------------------------------------------------------
hdr("figure")
cellp <- aggregate(cbind(any_bidi, any_cig) ~ year + ntcp, data = ntcp, FUN = mean)
long <- rbind(
  data.frame(year = cellp$year, ntcp = cellp$ntcp, y = 100 * cellp$any_bidi, panel = "Bidi"),
  data.frame(year = cellp$year, ntcp = cellp$ntcp, y = 100 * cellp$any_cig,  panel = "Cigarettes"))
long$Group <- ifelse(long$ntcp == 1, "NTCP districts", "Control districts")
long$x <- as.integer(long$year)

p <- ggplot(long, aes(x, y, colour = Group, group = Group)) +
  annotate("rect", xmin = 2, xmax = 3, ymin = -Inf, ymax = Inf,
           fill = "grey85", alpha = 0.35) +
  annotate("text", x = 2.5, y = Inf, label = "NTCP rolled out 2007-09",
           vjust = 1.6, size = 3, colour = "grey30") +
  geom_line(linewidth = 0.9) + geom_point(size = 2) +
  facet_wrap(~ panel, scales = "free_y") +
  scale_x_continuous(breaks = 1:3, labels = levels(ntcp$year)) +
  scale_colour_manual(values = c("Control districts" = "#1f2933",
                                 "NTCP districts" = "#c05621")) +
  labs(x = NULL, y = "Households reporting any\nconsumption (%)", colour = NULL) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "top", panel.grid.minor = element_blank(),
        strip.text = element_text(face = "bold", hjust = 0),
        plot.margin = margin(6, 12, 6, 4))
ggsave("trends.png", p, width = 8.4, height = 3.4, dpi = 200, bg = "white")
cat("wrote trends.png\n")

cat("\n\n##### end #####\n")
