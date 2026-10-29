# Replicating a published difference-in-differences

A teaching replication of:

> Nazar GP, Chang KC-M, Srivastava S, Pearce N, Karan A, Millett C (2020).
> *Impact of India's National Tobacco Control Programme on bidi and cigarette
> consumption: a difference-in-differences analysis.* **Tobacco Control**
> 29:103–110.

The paper asks whether the National Tobacco Control Programme, rolled out
across 42 districts in 2007–09, reduced household tobacco consumption. It uses
three rounds of the NSS Consumer Expenditure Survey and finds **no significant
effect**.

This repository rebuilds that analysis from the raw NSS files. It is built for
teaching, so the awkward parts are kept in view rather than tidied away.

**If you are a student, start with
[`exercise/ntcp-exercise.pdf`](exercise/ntcp-exercise.pdf).** The exercise is
pages 1-3 and the worked solutions are pages 4-9. Your instructor will give you
the cleaned data file separately; see **Data** below.

## Running it

```bash
python3 code/parse_r55.py            # round 55 district codes, from the PDF
python3 code/01_build_concordance.py # match 42 NTCP districts across 3 rounds
Rscript  code/02_extract_tobacco.R   # bidi/cigarette sticks from Block 5
Rscript  code/03_build_analysis.R    # merge, flag treatment, stack
Rscript  code/04_did.R               # the two-part DiD
Rscript  code/05_figure.R            # unadjusted trends
Rscript  code/06_student_file.R      # the file handed to students
```

Needs R with `haven`, `sandwich`, `lmtest`, `ggplot2`, and Python with
`pymupdf`.

## What it finds

Three of the paper's four estimates reproduce as nulls. One does not.

| Outcome | Paper (42 districts) | Here (21 districts) |
|:--|:--|:--|
| Any bidi (OR) | 1.03 [0.84, 1.28] | 1.40 [0.84, 2.35] |
| Any cigarette (OR) | 1.01 [0.82, 1.26] | **1.80 [1.14, 2.82]** |
| Bidi sticks/person (log) | 0.07 [−0.13, 0.28] | −0.06 [−0.34, 0.21] |
| Cigarette sticks/person (log) | −0.002 [−0.26, 0.26] | 0.10 [−0.19, 0.38] |

The paper's substantive conclusion survives: the NTCP districts show no
reduction relative to controls. Our confidence intervals are roughly twice as
wide, which is what half the treated districts buys you.

The cigarette-prevalence estimate is significant here and was not in the paper.
It should be read against everything in "Where this departs from the paper"
below rather than as a finding.

**All four pre-trend tests (DID1) are insignificant**, consistent with the
paper's own check.

## The part that is actually hard

The regressions are twenty lines. The district concordance took far longer, and
it is where a replication like this quietly goes wrong.

**The three rounds do not share a coding scheme.** Round 55 was collected July
1999 – June 2000, before the November 2000 reorganisation that created
Jharkhand, Uttarakhand and Chhattisgarh, so it uses the pre-2001 NSS state
list. Uttar Pradesh is state 25 in round 55 and state 09 in rounds 61 and 68.
Applying one scheme to all three silently relabels every state.

**Item codes move too.** Bidi and cigarettes are items 320 and 321 in rounds 55
and 61, but 310 and 311 in round 68. Reading round 68 with 320/321 returns
ganja and toddy, with no error.

**District names are not district names.** Khandwa is listed as *E. Nimar*.
Jamshedpur is *Singhbhum (E)* in round 61 and *Purbi Singhbhum* in round 68.
Aizawl is misspelled *Aizwal*. Sikkim and Delhi list districts as bare
directions, so "East Sikkim" must be looked up as "East".

Of the 42 NTCP districts, **21 could be matched unambiguously in all three
rounds**, and those are the ones used. Round 55 is the binding constraint: three
different parsing strategies all plateaued near 28 of 42, and several districts
genuinely did not exist under those names in 1999 — Delhi's districts and
Dimapur were created in 1997, Kancheepuram was still Chingleput.

**Two identifier columns, one of them a decoy.** The round-55 Block 5 file
carries both an `ID` column, which is the constant `"W3"`, and an `HHID`
column, which is the real key. Mistaking one for the other and rebuilding the
key from `Vill_Blk_Slno + SubRound + SubSample + Stage2_Stratum + Hhold_no`
looks safe, because `HHID` is exactly those five fields concatenated. It is
not: the `SubSample` column disagrees with the 7th digit of `HHID` in both the
Block 5 and the household file, so the reconstruction collapses pairs of
different households onto one key. That merged 19,122 round-55 households 2:1
and credited each with its twin's tobacco, inflating round-55 bidi prevalence
from 29% to 34%. The merge *rate* was 100% throughout, which is why only a
uniqueness check catches it. `03_build_analysis.R` now asserts the key is
unique.

**Every derived code is checked against the microdata** by counting households
in it. That check earned its place: it caught Sabarkantha being assigned to
Goa, because the regions PDF puts Goa's single entry directly above Gujarat's
block and the label ran on.

## Where this departs from the paper

Worth stating plainly, because these are the candidate explanations for the one
estimate that differs.

- **21 of 42 treated districts.** Not a random half — it is the half whose names
  were stable from 1999 to 2011, which may itself correlate with how much a
  district changed.
- **No survey weights.** The paper uses them; everything here is unweighted.
- **Fewer controls.** Sector, household size, wealth quintile within round, and
  state fixed effects. The paper adds religion, caste, employment type and the
  age and sex of the household head.
- **Round 68 recall.** The 68th round's schedule differs from earlier rounds,
  which is a known comparability problem for NSS consumption series and is not
  adjusted for here.
- Standard errors are clustered by district.

## Layout

```
data/ntcp_districts.csv        the 42 districts, from supplementary table S1
data/r55_districts.csv         round 55 district codes, parsed from the PDF
data/concordance.csv           every NTCP district x round, with match status
data/treatment_districts.csv   the 21 that resolved cleanly, used as treatment
data/analysis.rds              346,602 households, three rounds
output/did_results.txt         the estimates
output/trends.png              unadjusted trends, the picture behind the DiD
exercise/ntcp.rds              the cleaned file given to students
exercise/ntcp-exercise.tex     the exercise and worked solutions
exercise/solutions.R           every number in that document
exercise/ntcp.rds              the cleaned file given to students
exercise/ntcp-exercise.tex     the exercise and worked solutions
exercise/solutions.R           every number in that document
```

## Data

Not included — NSS microdata is not ours to redistribute. The scripts expect:

- rounds 55, 61, 68 household files in `../nss-consumption-panel/data/interim/`
- round 55 Block 5 (SPSS) and round 68 Block 5 (Stata) as downloaded from MoSPI
- round 61 Block 5 in `~/nss_ces/r61/`

Paths are at the top of each script.

## Licence

[CC BY 4.0](LICENSE). Use it, adapt it, teach with it; please cite the original
paper for the findings and this repository for the exercise.
