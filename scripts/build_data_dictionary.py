#!/usr/bin/env python3
# One-off: convert the EPA data-dictionary PDFs to Markdown. Handles the ICIS 4-column
# (Field/Type/Len/Description) layout and the AFS/Pipeline 2-column (Field/Description) layout.
import sys, re, pdfplumber

TYPES = {"Char", "Num", "Date", "Numeric", "Number", "Varchar", "Varchar2", "Integer"}
IDENT = re.compile(r"^[A-Z][A-Z0-9_]*$")
LEN   = re.compile(r"^(\d+|[—–-])$")
BLOCK = re.compile(r"^[A-Z][A-Za-z]+ block$")

def lines_of(page):
    words = sorted(page.extract_words(use_text_flow=False, keep_blank_chars=False),
                   key=lambda w: (w["top"], w["x0"]))
    lines = []
    for w in words:
        if lines and abs(lines[-1][0]["top"] - w["top"]) <= 3:
            lines[-1].append(w)
        else:
            lines.append([w])
    return [sorted(l, key=lambda x: x["x0"]) for l in lines]

def parse_pdf(path):
    tables, cur, mode = [], None, "2"
    with pdfplumber.open(path) as pdf:
        for page in pdf.pages:
            for ws in lines_of(page):
                toks = [w["text"] for w in ws]; text = " ".join(toks).strip()
                if not text:
                    continue
                csv = [t for t in toks if t.lower().rstrip(".,").endswith(".csv")]
                if csv and (len(toks) <= 3 or toks[0].rstrip(":").lower() == "file"):
                    cur = {"file": csv[0].rstrip(".,"), "desc": "", "fields": [], "mode": "2"}
                    tables.append(cur); continue
                if cur is None:
                    continue
                if re.match(r"^Field\s+Type\s+Len\s+Description", text): cur["mode"] = "4"; continue
                if re.match(r"^Field\s+Description\s*$", text) or BLOCK.match(text):    continue

                is_field = IDENT.match(toks[0])
                if is_field and cur["mode"] == "4":                       # Field Type Len Description
                    i, nm = 0, []
                    while i < len(toks) and (IDENT.match(toks[i]) or toks[i] == "/") and toks[i] not in TYPES:
                        nm.append(toks[i]); i += 1
                    rest = toks[i:]; typ = length = ""; d = rest
                    if rest and rest[0] in TYPES:
                        typ = rest[0]
                        if len(rest) > 1 and LEN.match(rest[1]): length, d = rest[1], rest[2:]
                        else: d = rest[1:]
                    if nm:
                        cur["fields"].append([" ".join(nm), typ, ("" if length in ("—","–","-") else length), " ".join(d)])
                        continue
                elif is_field and cur["mode"] == "2":                     # Field | Description (split at biggest gap)
                    gaps = [(ws[i+1]["x0"] - ws[i]["x1"], i) for i in range(len(ws) - 1)]
                    if gaps:
                        g, gi = max(gaps)
                        if g > 16:
                            cur["fields"].append([" ".join(toks[:gi+1]), "", "", " ".join(toks[gi+1:])])
                            continue
                # continuation line -> append to the previous field's description (or the table description)
                if cur["fields"]:
                    cur["fields"][-1][3] = (cur["fields"][-1][3] + " " + text).strip()
                else:
                    cur["desc"] = (cur["desc"] + " " + text).strip()
    return tables

_STOP = {"or", "and", "of", "to", "the", "a", "in", "for", "with", "per"}
def clean(s):
    # rejoin line-break hyphenation ("OPERAT- ING" -> "OPERATING") but keep suspended hyphens ("Five- or")
    s = re.sub(r"(\w)- (\w+)", lambda m: m.group(0) if m.group(2).lower() in _STOP else m.group(1) + m.group(2), s)
    return s.replace("|", "\\|").strip()

def esc(s): return clean(s)

def emit(tables, title):
    out = [f"## {title}\n"]
    for t in tables:
        out.append(f"### `{t['file']}`\n")
        if t["desc"]:
            out.append(re.sub(r"\s+\d+$", "", clean(t["desc"])) + "\n")   # drop stray trailing page-number
        if t["mode"] == "4":
            out += ["| Field | Type | Len | Description |", "|---|---|---|---|"]
            out += [f"| `{esc(n)}` | {ty} | {ln} | {esc(d)} |" for n, ty, ln, d in t["fields"]]
        else:
            out += ["| Field | Description |", "|---|---|"]
            out += [f"| `{esc(n)}` | {esc(d)} |" for n, ty, ln, d in t["fields"]]
        out.append("")
    return "\n".join(out)

HEADER = """# CAA Regulatory Data — Data Dictionary

Field-level documentation for every raw source in this repository, transcribed from EPA's official
published data dictionaries. Each entry lists the source CSV, a one-line description, and every field
with its type/length (where EPA publishes them) and definition.

**Sources:** EPA ECHO data downloads — ICIS-Air, AFS (the pre-2014 Air Facility System), and the CAA
Compliance Pipeline. See <https://echo.epa.gov/tools/data-downloads/>. Source PDFs are in
`docs/data_dictionaries/`; regenerate this file with `python3 scripts/build_data_dictionary.py`.

> A few descriptions inherit run-together words (missing spaces) from the source PDFs; field names,
> types, and lengths are exact.
"""

SOURCES = [("icis_air_data_dictionary.pdf", "ICIS-Air"),
           ("afs_data_dictionary.pdf",      "AFS (Air Facility System — pre-2014)"),
           ("pipeline_data_dictionary.pdf", "CAA Compliance Pipeline")]

if __name__ == "__main__":
    import os
    here = os.path.dirname(os.path.abspath(__file__))
    ddir = os.path.join(here, "..", "docs", "data_dictionaries")
    parts = [HEADER]
    for pdf, title in SOURCES:
        parts.append("---\n")
        parts.append(emit(parse_pdf(os.path.join(ddir, pdf)), title))
    out = os.path.join(here, "..", "docs", "data_dictionary.md")
    with open(out, "w") as f:
        f.write("\n".join(parts))
    print("wrote docs/data_dictionary.md")
