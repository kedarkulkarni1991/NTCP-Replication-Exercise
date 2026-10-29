#!/usr/bin/env python3
"""
Parse the NSS 55th round "List of NSS Regions and their Composition" by word
position rather than by reading order.

The document is a real table.  Reading it as a stream of text interleaves the
two district columns, which is why a line-based parser pairs names with the
wrong codes.  Reconstructing it from the x/y coordinates of each word avoids
that entirely.

Column layout, taken from the header row:

    (1) srl.no   (2) state (code)   (3) SR   (4) description
    (5) district name   (6) code    (7) district name   (8) code

Writes r55_districts.csv with state_name, state_code, dist_name, dist_code.
"""

import csv
import re
import sys
from collections import defaultdict
from pathlib import Path

import fitz

ROOT = Path(__file__).resolve().parents[1]
PDF = (Path.home() / "Library/CloudStorage/OneDrive-AzimPremjiFoundation"
       / "NSS Consumption Datasets/NSS 55th round"
       / "List_Of_NSS_Regions_And_Their_Composition.pdf")

# x-ranges for the columns that matter, read off the header positions
COLS = {
    "state": (90, 175),
    "nameA": (255, 350),
    "codeA": (350, 384),
    "nameB": (384, 458),
    "codeB": (458, 505),
}

CODE_RE = re.compile(r"^\((\d{1,2})\)$")

# words from the running header and the column headings, which sit in the same
# x-band as the state name and would otherwise be read as one
HEADER_WORDS = {
    "list", "of", "nss", "regions", "and", "their", "composition", "srl",
    "no", "no.", "state", "u.t.", "state/u.t.", "code", "(code)", "sr",
    "description", "name", "district", "detailed", "region", "i", "ii",
}


def column_of(x):
    for name, (lo, hi) in COLS.items():
        if lo <= x < hi:
            return name
    return None


def parse():
    doc = fitz.open(PDF)
    out = []
    state_name, state_code = None, None
    # the name currently being accumulated in each district column
    pending = {"A": [], "B": []}
    # state names wrap across rows ("Arunachal" / "Pradesh"), so build them up
    # and commit when the state's "(code)" appears
    state_buf = []

    for page in doc:
        rows = defaultdict(lambda: defaultdict(list))
        for x0, y0, _x1, _y1, word, *_ in page.get_text("words"):
            col = column_of(x0)
            if col:
                rows[round(y0 / 3.0)][col].append((x0, word))

        for key in sorted(rows):
            row = rows[key]
            cell = {c: " ".join(w for _, w in sorted(v)) for c, v in row.items()}

            # --- state column: either a name or its "(code)" ---
            if "state" in cell:
                txt = cell["state"].strip()
                m = CODE_RE.match(txt)
                if m:
                    # the code closes whatever name has been accumulating
                    if state_buf:
                        state_name = " ".join(state_buf).lower()
                        state_buf = []
                    state_code = int(m.group(1))
                    pending["A"].clear()
                    pending["B"].clear()
                elif (re.fullmatch(r"[A-Za-z][A-Za-z .&'-]{2,}", txt)
                      and txt.lower() not in HEADER_WORDS):
                    state_buf.append(txt)

            # --- the two district columns ---
            for tag, ncol, ccol in (("A", "nameA", "codeA"), ("B", "nameB", "codeB")):
                name = cell.get(ncol, "").strip()
                code = cell.get(ccol, "").strip()

                if name and not CODE_RE.match(name):
                    pending[tag].append(name)

                m = CODE_RE.match(code) if code else None
                if m:
                    full = " ".join(pending[tag]).strip()
                    pending[tag].clear()
                    if full and state_name:
                        out.append((state_name, state_code, full, int(m.group(1))))

    return out


def main():
    rows = parse()
    # a district with no state code is unusable
    rows = [r for r in rows if r[1] is not None]

    seen, uniq = set(), []
    for r in rows:
        k = (r[1], r[3])
        if k not in seen:
            seen.add(k)
            uniq.append(r)

    out = ROOT / "data/r55_districts.csv"
    with open(out, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["state_name", "state_code", "dist_name", "dist_code"])
        w.writerows(uniq)

    print(f"parsed {len(rows)} rows, {len(uniq)} unique (state, district) pairs")
    print(f"states seen: {len({r[1] for r in uniq})}")
    print(f"wrote {out}\n")

    probe = ["Guntur", "Hyderabad", "Kamrup", "Jorhat", "Cooch", "Dhanbad",
             "Patna", "Chingleput", "Jhunjhunu", "Dimapur", "Dhalai", "Goa"]
    for nm in probe:
        hit = [r for r in uniq if nm.lower() in r[2].lower()]
        shown = "; ".join(f"{r[0]} {r[1]}/{r[3]} {r[2]}" for r in hit[:3])
        print(f"  {nm:12s} {shown if shown else '--'}")


if __name__ == "__main__":
    sys.exit(main())
