"""
synthesize_extension_yaml.py -- generate data/raw/minimum_wage/extension/2023-onward.yaml
                                 from VZ + DOL WHD + EPI snapshots.

Author - Ben Glasner
Research title - EIG Wage Figure Explain Everything
Research question - what share of US wage and salary workers are constrained by their
                    applicable (federal, state, county, or city) minimum wage,
                    1979 through present?

This is an offline ETL utility. The R pipeline (code/20b_extend-minimum-wage-forward.R)
reads the YAML this script produces; it does not run this script. Re-run this script
manually when source snapshots are refreshed (DOL WHD HTML, EPI tracker HTML).

Inputs:
  - data/raw/minimum_wage/vz_release/v1.4.0/mw_state_stata/mw_state_annual.dta
  - data/raw/minimum_wage/sources/dol_whd/<DATE>/state-minimum-wage-history.html
  - data/raw/minimum_wage/extension/sources_parsed/epi_changes_extracted.csv
    (which is itself produced by parsing data/raw/minimum_wage/sources/epi/<DATE>/minimum-wage-tracker.html)
  - data/raw/minimum_wage/concordance/county_to_locality.csv
  - data/raw/minimum_wage/concordance/individcc_to_locality.csv
    (read for cross-validation only -- the synthesizer warns if a substate
    event references a slug that is not in either concordance, but this is
    not fatal: documented-limitation localities like Belmont and Cupertino
    appear in YAML without concordance entries because IPUMS-CPS cannot
    separately identify them; see the binding-validation report that
    code/20e_binding-minimum-analysis.R writes to output/verification/.)

Output:
  - data/raw/minimum_wage/extension/2023-onward.yaml

Synthesis rules:
  - State 2023 rate: from DOL WHD 2023 column, default Jan 1 effective date.
  - State 2024 rate: from DOL WHD 2024 column, default Jan 1 effective date.
  - State 2025 indexed step: inferred from EPI rate_from of the first EPI 2025+ event
    when that rate_from differs from DOL 2024. Default Jan 1 effective date.
  - State 2025+ explicit changes: from EPI tracker, with explicit effective dates.
  - Sub-state changes: EPI only (DOL WHD does not track sub-state).
  - Federal: not emitted (federal MW unchanged since 2009-07-24).
  - States with no state MW (Alabama, Florida, etc. pre-2021): zero entries.

Locality slug rule (added 2026-05-05):
  Every substate event carries a stable locality_id slug used downstream
  as the join key. Slugs are <state_abbr_lower>_<snake_case_of_locality>;
  apostrophes (straight ' and curly U+2019) are stripped before slug
  derivation, '&' becomes 'and', and runs of non-alphanumerics collapse
  to a single underscore. Specific aliases that collapse multiple
  free-text forms into one slug (notably the New York tri-county
  "Long Island & Westchester" / "Nassau, Suffolk, and Westchester
  Counties" pair, which both resolve to ny_li_westchester) are listed
  in LOCALITY_SLUG_OVERRIDES below. The slug derivation MUST stay in
  sync with the slug rule applied in code/20c_build-binding-minimum-panel.R;
  the synthesizer cross-checks emitted slugs against the concordance
  files and prints a warning for any slug not covered.

Provenance: every entry carries source name, source URL, and an
inferred_effective_date flag for human audit.
"""

import csv
import os
import re
import sys
from io import StringIO

import pandas as pd
import yaml


# ----------------------------- configuration ---------------------------------

REPO_ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))

VZ_ANNUAL_DTA = os.path.join(
    REPO_ROOT, "data", "raw", "minimum_wage",
    "vz_release", "v1.4.0", "mw_state_stata", "mw_state_annual.dta"
)
DOL_HISTORY_HTML = os.path.join(
    REPO_ROOT, "data", "raw", "minimum_wage",
    "sources", "dol_whd", "2026-05-04", "state-minimum-wage-history.html"
)
EPI_CHANGES_CSV = os.path.join(
    REPO_ROOT, "data", "raw", "minimum_wage", "extension",
    "sources_parsed", "epi_changes_extracted.csv"
)
COUNTY_CONCORDANCE_CSV = os.path.join(
    REPO_ROOT, "data", "raw", "minimum_wage", "concordance", "county_to_locality.csv"
)
INDIVIDCC_CONCORDANCE_CSV = os.path.join(
    REPO_ROOT, "data", "raw", "minimum_wage", "concordance", "individcc_to_locality.csv"
)
OUTPUT_YAML = os.path.join(
    REPO_ROOT, "data", "raw", "minimum_wage", "extension", "2023-onward.yaml"
)

DOL_URL = "https://www.dol.gov/agencies/whd/state/minimum-wage/history"
EPI_URL = "https://www.epi.org/minimum-wage-tracker/"

DOL_SOURCE_NAME = "DOL_WHD_history_2026-05-04"
EPI_SOURCE_NAME = "EPI_tracker_2026-05-04"
EPI_INFERRED_SOURCE_NAME = "EPI_tracker_2026-05-04_inferred"


# State name -> state abbreviation lookup, sourced from the VZ annual file at
# main() time.
STATE_NAME_TO_ABBR: dict = {}


# Slug overrides -- (state_abbr, locality) pairs whose slug does not follow
# the deterministic rule. Keep this list small and documented; every entry
# represents an alias collapse that the deterministic slugifier cannot
# infer on its own.
LOCALITY_SLUG_OVERRIDES = {
    # New York tri-county. Vaghul-Zipperer's substate panel uses
    # "Long Island & Westchester"; the EPI tracker reports the same
    # ordinance as "Nassau, Suffolk, and Westchester Counties". Both
    # forms collapse to ny_li_westchester to keep the join key stable.
    ("NY", "Long Island & Westchester"): "ny_li_westchester",
    ("NY", "Nassau, Suffolk, and Westchester Counties"): "ny_li_westchester",
}


# ----------------------------- helpers ---------------------------------------

def _try_float(s):
    try:
        float(s.strip())
        return True
    except (ValueError, AttributeError):
        return False


def clean_dol_cell(raw):
    """Apply the same cleaning rules as 20b_extend-minimum-wage-forward.R."""
    if pd.isna(raw):
        return None
    s = str(raw).strip()
    s = re.sub(r"\([a-z0-9,\s]+\)|\[[a-z0-9,\s]+\]", "", s).strip()
    if s == "...":
        return None
    s = s.replace("–", "-").replace("..", ".").replace("`", "").strip()
    if "/wk" in s or "/day" in s:
        return None
    s = s.replace("$", "").strip()
    if not s:
        return None
    if "&" in s or "/" in s:
        nums = [float(p.strip()) for p in re.split(r"&|/", s) if _try_float(p)]
        return max(nums) if nums else None
    if "-" in s:
        nums = [float(p.strip()) for p in s.split("-") if _try_float(p)]
        return max(nums) if nums else None
    try:
        return float(s)
    except ValueError:
        return None


def round2(x):
    return None if x is None or pd.isna(x) else round(float(x), 2)


def slugify_locality(state_abbr, locality):
    """Derive the canonical locality_id slug for a (state, locality) pair.

    Applies the override table first, then falls back to a deterministic
    rule: lowercase, strip both ASCII and curly apostrophes, replace '&'
    with 'and', collapse other non-alphanumerics to underscores, and
    prefix with the state abbreviation in lowercase.
    """
    key = (state_abbr.upper(), locality)
    if key in LOCALITY_SLUG_OVERRIDES:
        return LOCALITY_SLUG_OVERRIDES[key]
    s = locality.lower()
    s = s.replace("'", "").replace("’", "")
    s = s.replace("&", "and")
    s = re.sub(r"[^a-z0-9]+", "_", s)
    s = s.strip("_")
    return f"{state_abbr.lower()}_{s}"


def load_concordance_slugs():
    """Read locality_id_chr columns from both concordance CSVs."""
    slugs = set()
    for path in (COUNTY_CONCORDANCE_CSV, INDIVIDCC_CONCORDANCE_CSV):
        if not os.path.exists(path):
            print(f"warning: concordance not found at {path}; skipping slug load.")
            continue
        with open(path, encoding="utf-8", newline="") as f:
            reader = csv.DictReader(f)
            for row in reader:
                slug = (row.get("locality_id_chr") or "").strip()
                if slug:
                    slugs.add(slug)
    return slugs


# ----------------------------- main ------------------------------------------

def main():
    vz = pd.read_stata(VZ_ANNUAL_DTA)
    vz["year_int"] = pd.to_datetime(vz["year"]).dt.year
    vz_2022 = vz[vz["year_int"] == 2022][["statefips", "statename", "stateabb", "max_mw"]].copy()
    vz_2022.rename(columns={"max_mw": "vz_2022_rate"}, inplace=True)

    vz22 = dict(zip(vz_2022["statename"], vz_2022["vz_2022_rate"]))
    vz_fips = dict(zip(vz_2022["statename"], vz_2022["statefips"]))
    vz_abbr = dict(zip(vz_2022["statename"], vz_2022["stateabb"]))
    STATE_NAME_TO_ABBR.update(vz_abbr)

    with open(DOL_HISTORY_HTML, encoding="utf-8") as f:
        dol_html = f.read()
    dol_tables = pd.read_html(StringIO(dol_html))
    dol_wide = dol_tables[0].rename(columns={dol_tables[0].columns[0]: "jurisdiction"})
    for i in range(1, 6):
        tt = dol_tables[i].rename(columns={dol_tables[i].columns[0]: "jurisdiction"})
        dol_wide = dol_wide.merge(tt, on="jurisdiction", how="left")
    dol_wide["dol_2023"] = dol_wide["2023"].apply(clean_dol_cell)
    dol_wide["dol_2024"] = dol_wide["2024"].apply(clean_dol_cell)

    territories = ["Puerto Rico", "Guam", "American Samoa", "U.S. Virgin Islands"]
    dol_state = dol_wide[
        ~dol_wide["jurisdiction"].isin(territories)
        & (dol_wide["jurisdiction"] != "Federal (FLSA)")
    ][["jurisdiction", "dol_2023", "dol_2024"]]
    dol_state = dol_state.rename(columns={"jurisdiction": "vz_statename"})
    dol23 = dict(zip(dol_state["vz_statename"], dol_state["dol_2023"]))
    dol24 = dict(zip(dol_state["vz_statename"], dol_state["dol_2024"]))

    epi = pd.read_csv(EPI_CHANGES_CSV)
    epi["locality"] = epi["locality"].fillna("")
    epi_state_remap = {"Federal": "__FEDERAL__", "Washington D.C.": "District of Columbia"}
    epi["vz_statename"] = epi["jurisdiction_state"].map(
        lambda x: epi_state_remap.get(x, x)
    )

    state_changes = []

    for sn in sorted(vz22):
        fips = int(vz_fips[sn]) if not pd.isna(vz_fips[sn]) else None
        abbr = vz_abbr[sn]
        d23 = dol23.get(sn)
        d24 = dol24.get(sn)
        last_rate = float(vz22[sn])

        if d23 is not None and abs(d23 - last_rate) > 0.005:
            state_changes.append({
                "jurisdiction": sn, "state_abbr": abbr, "state_fips": fips,
                "effective_date": "2023-01-01",
                "rate_min": round2(d23), "rate_tipped": None,
                "inferred_effective_date": True,
                "source": DOL_SOURCE_NAME, "source_url": DOL_URL,
                "notes": "Year-over-year change inferred from DOL WHD annual table; effective date defaults to Jan 1.",
            })
            last_rate = float(d23)
        if d24 is not None and abs(d24 - last_rate) > 0.005:
            state_changes.append({
                "jurisdiction": sn, "state_abbr": abbr, "state_fips": fips,
                "effective_date": "2024-01-01",
                "rate_min": round2(d24), "rate_tipped": None,
                "inferred_effective_date": True,
                "source": DOL_SOURCE_NAME, "source_url": DOL_URL,
                "notes": "Year-over-year change inferred from DOL WHD annual table; effective date defaults to Jan 1.",
            })
            last_rate = float(d24)

        state_epi = epi[
            (epi["vz_statename"] == sn) & (epi["locality"] == "")
            & (epi["effective_date"] >= "2025-01-01")
        ].copy().sort_values("effective_date")

        first_evt_dates = state_epi[state_epi["rate_kind"] == "min_wage"]["effective_date"].unique()
        if len(first_evt_dates):
            first_date = first_evt_dates[0]
            first_evt = state_epi[
                (state_epi["rate_kind"] == "min_wage") & (state_epi["effective_date"] == first_date)
            ].iloc[0]
            rate_from = first_evt.get("rate_from")
            if (
                first_date > "2025-01-01"
                and pd.notna(rate_from)
                and d24 is not None
                and abs(rate_from - d24) > 0.005
            ):
                tip_first = state_epi[
                    (state_epi["rate_kind"] == "tip_wage") & (state_epi["effective_date"] == first_date)
                ]
                tip_rate_from = tip_first.iloc[0]["rate_from"] if len(tip_first) else None
                state_changes.append({
                    "jurisdiction": sn, "state_abbr": abbr, "state_fips": fips,
                    "effective_date": "2025-01-01",
                    "rate_min": round2(rate_from),
                    "rate_tipped": round2(tip_rate_from) if pd.notna(tip_rate_from) else None,
                    "inferred_effective_date": True,
                    "source": EPI_INFERRED_SOURCE_NAME, "source_url": EPI_URL,
                    "notes": (
                        f"Indexed Jan 1, 2025 step inferred from EPI rate_from of subsequent "
                        f"{first_date} change ({rate_from} -> {first_evt['rate_to']}). "
                        f"Default Jan 1 effective date."
                    ),
                })
                last_rate = float(rate_from)

        for evdate, group in state_epi.groupby("effective_date"):
            mwrows = group[group["rate_kind"] == "min_wage"]
            tprows = group[group["rate_kind"] == "tip_wage"]
            if not len(mwrows):
                continue
            mw = mwrows.iloc[0]
            state_changes.append({
                "jurisdiction": sn, "state_abbr": abbr, "state_fips": fips,
                "effective_date": evdate,
                "rate_min": round2(mw["rate_to"]),
                "rate_tipped": round2(tprows.iloc[0]["rate_to"]) if len(tprows) else None,
                "inferred_effective_date": False,
                "source": EPI_SOURCE_NAME, "source_url": EPI_URL,
                "notes": mw["source_text"] if not pd.isna(mw["source_text"]) else "",
            })

    substate_changes = []
    sub = epi[(epi["locality"] != "") & (epi["effective_date"] >= "2023-01-01")].copy()
    for (sn, loc), grp in sub.groupby(["vz_statename", "locality"]):
        fips = int(vz_fips[sn]) if sn in vz_fips else None
        abbr = vz_abbr.get(sn, "")
        slug = slugify_locality(abbr, loc) if abbr else None
        for evdate, daygrp in grp.groupby("effective_date"):
            mwrows = daygrp[daygrp["rate_kind"] == "min_wage"]
            tprows = daygrp[daygrp["rate_kind"] == "tip_wage"]
            if not len(mwrows):
                continue
            mw = mwrows.iloc[0]
            substate_changes.append({
                "jurisdiction_state": sn, "state_abbr": abbr, "state_fips": fips,
                "locality": loc, "locality_id": slug,
                "effective_date": evdate,
                "rate_min": round2(mw["rate_to"]),
                "rate_tipped": round2(tprows.iloc[0]["rate_to"]) if len(tprows) else None,
                "inferred_effective_date": False,
                "source": EPI_SOURCE_NAME, "source_url": EPI_URL,
                "notes": mw["source_text"] if not pd.isna(mw["source_text"]) else "",
            })

    missing_slug = [
        ev for ev in substate_changes
        if not ev.get("locality_id") or not isinstance(ev["locality_id"], str)
    ]
    if missing_slug:
        msg_lines = ["synthesize_extension_yaml.py -- substate events missing locality_id:"]
        for ev in missing_slug:
            msg_lines.append(
                f"  {ev.get('effective_date')} | "
                f"{ev.get('jurisdiction_state')} | {ev.get('locality')!r}"
            )
        msg_lines.append(
            "Add a slug for each missing locality (in LOCALITY_SLUG_OVERRIDES "
            "or via the deterministic slugifier) before re-running."
        )
        raise ValueError("\n".join(msg_lines))

    emitted_slugs = {ev["locality_id"] for ev in substate_changes}
    concordance_slugs = load_concordance_slugs()

    fallback_slugs = sorted(emitted_slugs - concordance_slugs)
    dead_slugs = sorted(concordance_slugs - emitted_slugs)

    if fallback_slugs:
        preview = fallback_slugs[:10]
        suffix = "..." if len(fallback_slugs) > 10 else ""
        print(
            f"note: {len(fallback_slugs)} substate slug(s) emitted to YAML are not in "
            f"either concordance file (state-level fallback per documented limitation): "
            f"{preview}{suffix}"
        )
    if dead_slugs:
        print(
            f"note: {len(dead_slugs)} concordance slug(s) have no emitted YAML event "
            f"(VZ-only or stale concordance row): {dead_slugs}"
        )

    out = {
        "metadata": {
            "description": "Forward extension of Vaghul-Zipperer state and sub-state minimum wage panels, 2023-01-01 onward.",
            "generated_at": "2026-05-05",
            "generator": "code/_utils/synthesize_extension_yaml.py",
            "sources": [
                {"name": DOL_SOURCE_NAME, "url": DOL_URL,
                 "description": "U.S. DOL Wage and Hour Division historical state minimum wage table (annual rates 1968-2024)."},
                {"name": EPI_SOURCE_NAME, "url": EPI_URL,
                 "description": "EPI Minimum Wage Tracker (current rates plus most-recent and upcoming changes)."},
            ],
            "schema_version": "0.3",
            "effective_date_convention": "YYYY-MM-DD; inferred_effective_date=true marks dates defaulted to Jan 1 because the source provides only annual snapshots (DOL) or because the date is inferred from EPI rate_from of a subsequent event (indexed states).",
            "rate_units": "nominal USD per hour",
            "rate_min": "general state or local minimum wage",
            "rate_tipped": "cash subminimum for tipped workers; null if not separately documented",
            "locality_id": "stable snake_case slug for substate events (e.g., ca_san_francisco). Used as the join key in 20c/20d. State events do not carry locality_id.",
            "change_log": [
                "v0.1 -> v0.2: added inferred Jan 1, 2025 step events for indexed states whose EPI rate_from differs from DOL 2024 rate.",
                "v0.2 -> v0.3 (2026-05-05): every substate event now carries locality_id (stable slug) to fix the New York tri-county join failure and to harden the join against free-text drift.",
            ],
        },
        "state_changes": state_changes,
        "substate_changes": substate_changes,
    }

    with open(OUTPUT_YAML, "w", encoding="utf-8") as f:
        yaml.safe_dump(out, f, sort_keys=False, default_flow_style=False, width=120, allow_unicode=True)

    print(f"Wrote {OUTPUT_YAML}")
    print(f"State changes: {len(state_changes)}")
    print(f"Sub-state changes: {len(substate_changes)}")
    print(f"Distinct substate slugs: {len(emitted_slugs)}")


if __name__ == "__main__":
    try:
        main()
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
