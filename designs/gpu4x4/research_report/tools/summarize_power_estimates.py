#!/usr/bin/env python3
"""Extract matched OpenLane typical-corner power reports to a CSV."""

import csv
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]
REPORT_DIR = ROOT / "designs/gpu4x4/research_report"
RUNS_CSV = REPORT_DIR / "data/physical_runs.csv"
OUTPUT_CSV = REPORT_DIR / "data/power_estimates.csv"
POWER_FIELDS = (
    "typical_internal_W",
    "typical_switching_W",
    "typical_leakage_W",
    "typical_total_W",
)


def main():
    with RUNS_CSV.open(newline="") as stream:
        runs = list(csv.DictReader(stream))
    if {row["variant"] for row in runs} != {"D", "I", "IB"}:
        raise ValueError(f"Expected exactly the D, I, and IB runs in {RUNS_CSV}")

    output_rows = []
    for run in runs:
        power_report = (
            ROOT
            / run["openlane_run_dir"]
            / "reports/signoff/31-rcx_sta.power.rpt"
        )
        report_text = power_report.read_text()
        try:
            typical_section = report_text.split("Typical Corner", 1)[1]
        except IndexError as error:
            raise ValueError(f"Missing typical corner in {power_report}") from error
        match = re.search(
            r"^\s*Total\s+"
            r"([0-9.eE+-]+)\s+([0-9.eE+-]+)\s+([0-9.eE+-]+)\s+"
            r"([0-9.eE+-]+)",
            typical_section,
            re.MULTILINE,
        )
        if match is None:
            raise ValueError(f"Missing typical-corner total power in {power_report}")
        values = [float(value) for value in match.groups()]
        if any(value < 0 for value in values):
            raise ValueError(f"Invalid power values in {power_report}")

        output_rows.append(
            {
                "variant": run["variant"],
                **dict(zip(POWER_FIELDS, values)),
                "activity_annotation": "none_vectorless_tool_default",
                "source_report": (
                    Path(run["openlane_run_dir"])
                    / "reports/signoff/31-rcx_sta.power.rpt"
                ).as_posix(),
            }
        )

    OUTPUT_CSV.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT_CSV.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=output_rows[0].keys())
        writer.writeheader()
        writer.writerows(output_rows)
    print(f"Wrote {OUTPUT_CSV}")


if __name__ == "__main__":
    main()
