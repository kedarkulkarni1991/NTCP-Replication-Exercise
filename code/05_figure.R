## Unadjusted trends, the picture behind the DiD. Mirrors figures 1 and 2 of
## the paper. Parallel trends requires the two lines to move together before
## the programme, i.e. between 1999-2000 and 2004-05.
suppressMessages(library(ggplot2))
dat <- readRDS("data/analysis.rds")

cell <- aggregate(cbind(any_bidi, any_cig) ~ year + ntcp, data = dat, FUN = mean)
long <- rbind(
  data.frame(year = cell$year, ntcp = cell$ntcp, y = 100 * cell$any_bidi,
             panel = "Bidi"),
  data.frame(year = cell$year, ntcp = cell$ntcp, y = 100 * cell$any_cig,
             panel = "Cigarettes"))
long$Group <- ifelse(long$ntcp == 1, "NTCP districts", "Control districts")
long$x <- match(long$year, c("1999-2000", "2004-05", "2011-12"))

p <- ggplot(long, aes(x, y, colour = Group, group = Group)) +
  annotate("rect", xmin = 2, xmax = 3, ymin = -Inf, ymax = Inf,
           fill = "grey85", alpha = 0.35) +
  annotate("text", x = 2.5, y = Inf, label = "NTCP rolled out 2007-09",
           vjust = 1.6, size = 3, colour = "grey30") +
  geom_line(linewidth = 0.9) + geom_point(size = 2) +
  facet_wrap(~ panel, scales = "free_y") +
  scale_x_continuous(breaks = 1:3, labels = c("1999-2000", "2004-05", "2011-12")) +
  scale_colour_manual(values = c("Control districts" = "#1f2933",
                                 "NTCP districts" = "#c05621")) +
  labs(x = NULL, y = "Households reporting any consumption (%)", colour = NULL) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "top", panel.grid.minor = element_blank(),
        strip.text = element_text(face = "bold", hjust = 0),
        plot.margin = margin(6, 10, 6, 12))

ggsave("output/trends.png", p, width = 8.4, height = 3.4, dpi = 200, bg = "white")
cat("wrote output/trends.png\n")
print(long[order(long$panel, long$Group, long$x), c("panel","Group","year","y")], row.names = FALSE)
