#!/usr/bin/env python3
"""
Build the NTCP district concordance across NSS rounds 55, 61 and 68.

The three rounds do not share a coding scheme.  Round 55 (Jul 1999 - Jun 2000)
predates the November 2000 reorganisation, so Uttarakhand, Jharkhand and
Chhattisgarh do not exist and it uses the pre-2001 NSS state list; rounds 61 and
68 use the post-2001 list.  District codes are reissued as districts split.

Sources, one per round:
  55 : List_Of_NSS_Regions_And_Their_Composition.pdf   names + codes
  61 : nss61_districts.csv                             names + codes (complete)
  68 : Appendix_I_68.pdf                               names + codes

Rather than parse all ~600 districts out of two awkward multi-column PDFs, this
looks up only the 42 NTCP districts by name.  Every code it derives is then
checked against the actual microdata by 02_validate_codes.R, which is the real
safeguard: a code that no household carries is a parsing error.

Writes data/concordance.csv, one row per (round, NTCP district), with an
explicit status so that anything unresolved stays visible.
"""

import csv
import re
import sys
import unicodedata
from pathlib import Path

import fitz

ROOT = Path(__file__).resolve().parents[1]
HOME = Path.home()
NSSDATA = HOME / "Library/CloudStorage/OneDrive-AzimPremjiFoundation/NSS Consumption Datasets"

R55_PDF = NSSDATA / "NSS 55th round/List_Of_NSS_Regions_And_Their_Composition.pdf"
R61_CSV = NSSDATA / "NSS 61st round (emp-unemp)/interim/nss61_districts.csv"
R68_PDF = HOME / "nss_ces/r68/IHSN_Report_68_Round_sch_1pt0.pdf"


def norm(s):
    """Lowercase, drop accents, parentheticals and anything not a letter.

    A lone directional parenthetical is kept, because "Singhbhum (E)" and
    "Singhbhum (W)" are different districts and would otherwise collide.
    """
    s = str(s)
    for pat, word in ((r"\(\s*E\s*\)", " east"), (r"\(\s*W\s*\)", " west"),
                      (r"\(\s*N\s*\)", " north"), (r"\(\s*S\s*\)", " south")):
        s = re.sub(pat, word, s)
    s = re.sub(r"\([^)]*\)", " ", s)
    s = unicodedata.normalize("NFKD", s)
    s = "".join(c for c in s if not unicodedata.combining(c))
    return re.sub(r"[^a-z]", "", s.lower())


# How each NTCP district is spelled in the NSS documents.  Several of these are
# not alternative spellings but different names for the same place, and one
# (Khandwa / East Nimar) would be impossible to guess.
ALIASES = {
    "jorhat":        ["johrat"],
    "aizawl":        ["aizwal"],                  # NSS misspells it
    "villupuram":    ["viluppuram"],
    "khandwa":       ["enimar", "eastnimar"],     # Khandwa district = East Nimar
    "jamshedpur":    ["singhbhumeast", "eastsinghbhum", "purbisinghbhum"],
    "jhunjhunu":     ["jhunjhunun"],
    "newdelhi":      ["newdelhi"],
    "gulbarga":      ["kalaburagi"],
    "vadodara":      ["baroda"],
    "coochbehar":    ["koochbehar", "kochbihar", "coochbehar", "kochbehar"],
    "khurda":        ["khordha"],
    "munger":        ["monghyr"],
    "tehrigarhwal":  ["tehrigadhwal", "tehri"],
    "kancheepuram":  ["kanchipuram", "kanchepuram", "kancheepuram"],
    "bangalore":     ["bangaloreurban", "bengaluruurban"],
    "sabarkantha":   ["sabarkanta"],
}

# In Sikkim and Delhi the NSS lists districts by bare direction ("East",
# "South"), so "East Sikkim" must be looked up as "East" within that state.
DIRECTION_ONLY = {
    ("sikkim", "eastsikkim"):  "east",
    ("sikkim", "southsikkim"): "south",
    ("delhi",  "eastdelhi"):   "east",
}


def candidates(state, district):
    base = norm(district)
    out = {base}
    out.update(norm(a) for a in ALIASES.get(base, []))
    bare = DIRECTION_ONLY.get((norm(state), base))
    if bare:
        out.add(bare)
    if base == "kanpur":
        out.update({"kanpurnagar", "kanpurdehat"})
    return out


def load_ntcp():
    with open(ROOT / "data/ntcp_districts.csv") as fh:
        return list(csv.DictReader(fh))


# --------------------------------------------------------------------------
# Round 61 -- a clean CSV, so just read it.
# --------------------------------------------------------------------------
def entries_r61():
    out = []
    with open(R61_CSV) as fh:
        for row in csv.DictReader(fh):
            out.append((row["state_name"].strip(), int(row["state_code"]),
                        row["dist_name"].strip(), int(row["dist_code"])))
    return out


# --------------------------------------------------------------------------
# Round 55 -- "name" then "(code)" on the next line, inside a state block whose
# own "(code)" follows the state name.
# --------------------------------------------------------------------------
STATES_55 = [
    "andhra pradesh", "arunachal pradesh", "assam", "bihar", "goa", "gujarat",
    "haryana", "himachal pradesh", "jammu & kashmir", "karnataka", "kerala",
    "madhya pradesh", "maharashtra", "manipur", "meghalaya", "mizoram",
    "nagaland", "orissa", "punjab", "rajasthan", "sikkim", "tamil nadu",
    "tripura", "uttar pradesh", "west bengal", "delhi", "pondicherry",
    "chandigarh", "lakshadweep", "daman & diu", "dadra & nagar haveli",
    "andaman & nicobar islands",
]


def entries_r55():
    """Read the round-55 district list produced by parse_r55.py.

    That script reconstructs the regions table from word coordinates, because
    the two district columns interleave in reading order.  State names there
    are unreliable, so parse_r55.py relabels them from the pre-2001 NSS list,
    anchored on districts whose state is unambiguous (Assam 04, Bihar 05,
    Andhra Pradesh 02) and checked against district and household counts.
    """
    path = ROOT / "data/r55_districts.csv"
    if not path.exists():
        raise SystemExit("run code/parse_r55.py first")
    out = []
    with open(path) as fh:
        for row in csv.DictReader(fh):
            out.append((row["state_name"].strip(), int(row["state_code"]),
                        row["dist_name"].strip(), int(row["dist_code"])))
    return out


# --------------------------------------------------------------------------
# Round 68 -- the IHSN report prints the value labels of District_Code straight
# from the data file, as "ssdd / name / cases / percent".  That is the codebook
# of the microdata itself, so it is preferred over the layout appendix.
# --------------------------------------------------------------------------
def entries_r68():
    doc = fitz.open(R68_PDF)
    seen = {}
    for page in doc:
        lines = [x.strip() for x in page.get_text().split("\n")]
        for i, x in enumerate(lines):
            if re.fullmatch(r"\d{4}", x) and i + 1 < len(lines):
                nm = lines[i + 1]
                if re.fullmatch(r"[A-Za-z][A-Za-z .&'()/-]{1,60}", nm):
                    seen.setdefault(int(x), nm)
    out = []
    for code, nm in sorted(seen.items()):
        out.append(("", code // 100, nm, code % 100))
    return out


def match(ntcp_rows, entries, round_no):
    out = []
    for row in ntcp_rows:
        want = candidates(row["state"], row["district"])
        hits = [e for e in entries if norm(e[2]) in want]

        if round_no == 68:
            # this source carries no state names, so compare the state code
            want_sc = {h[1] for h in entries if norm(h[2]) in want}
            same_state = hits if len(want_sc) <= 1 else []
        else:
            same_state = [h for h in hits if norm(h[0]) == norm(row["state"])]
        if same_state:
            hits, how = same_state, "state+district"
        elif hits:
            # Round 55 predates the 2000 reorganisation, so a district may be
            # found under the state it belonged to then.
            how = "district only; state differs"
        else:
            how = "NOT FOUND"

        if hits:
            for h in hits:
                out.append(dict(round=round_no, phase=row["phase"],
                                ntcp_state=row["state"], ntcp_district=row["district"],
                                nss_state=h[0], state_code=h[1],
                                nss_district=h[2], district_code=h[3],
                                n_hits=len(hits), how=how))
        else:
            out.append(dict(round=round_no, phase=row["phase"],
                            ntcp_state=row["state"], ntcp_district=row["district"],
                            nss_state="", state_code="", nss_district="",
                            district_code="", n_hits=0, how=how))
    return out


def main():
    ntcp = load_ntcp()
    print(f"NTCP districts: {len(ntcp)}\n")

    allrows = []
    for rno, fn in ((55, entries_r55), (61, entries_r61), (68, entries_r68)):
        ent = fn()
        rows = match(ntcp, ent, rno)
        allrows += rows
        found = len({r["ntcp_district"] for r in rows if r["n_hits"] > 0})
        print(f"round {rno}: {len(ent):4d} district entries parsed, "
              f"{found}/{len(ntcp)} NTCP districts matched")

    out = ROOT / "data/concordance.csv"
    with open(out, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(allrows[0].keys()))
        w.writeheader()
        w.writerows(allrows)
    print(f"\nwrote {out}")

    for rno in (55, 61, 68):
        miss = sorted({r["ntcp_district"] for r in allrows
                       if r["round"] == rno and r["n_hits"] == 0})
        amb = sorted({r["ntcp_district"] for r in allrows
                      if r["round"] == rno and r["n_hits"] > 1})
        print(f"\nround {rno}")
        print(f"  unmatched ({len(miss)}): {', '.join(miss) if miss else 'none'}")
        print(f"  multiple  ({len(amb)}): {', '.join(amb) if amb else 'none'}")


if __name__ == "__main__":
    sys.exit(main())
