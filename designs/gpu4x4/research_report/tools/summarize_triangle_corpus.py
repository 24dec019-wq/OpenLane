#!/usr/bin/env python3
"""Summarize matched rasterizer cycle counts from oracle-checked corpus logs."""

import csv
import math
import statistics
import sys
from pathlib import Path


VARIANTS = ("direct", "incremental", "incremental_bbox")
CORPUS_SIZE = 136


def parse_log(path):
    cases = {}
    for line in path.read_text().splitlines():
        if not line.startswith("CORPUS_CASE "):
            continue
        fields = [int(field) for field in line.split()[1:]]
        if len(fields) != 8:
            raise ValueError(f"{path}: malformed corpus row: {line}")
        case_id, cycles, x0, y0, x1, y1, x2, y2 = fields
        if case_id in cases:
            raise ValueError(f"{path}: duplicate corpus case {case_id}")
        cases[case_id] = (cycles, (x0, y0, x1, y1, x2, y2))
    if len(cases) != CORPUS_SIZE or set(cases) != set(range(CORPUS_SIZE)):
        raise ValueError(
            f"{path}: expected case IDs 0..{CORPUS_SIZE - 1}, got {len(cases)}"
        )
    return cases


def signed_area(vertices):
    x0, y0, x1, y1, x2, y2 = vertices
    return (x1 - x0) * (y2 - y0) - (y1 - y0) * (x2 - x0)


def ceil_div16(value):
    return -((-value) // 16)


def candidate_pixels(vertices):
    xs = vertices[0::2]
    ys = vertices[1::2]
    x_min = max(0, ceil_div16(min(xs) - 8))
    x_max = min(15, (max(xs) - 8) // 16)
    y_min = max(0, ceil_div16(min(ys) - 8))
    y_max = min(15, (max(ys) - 8) // 16)
    if x_min > x_max or y_min > y_max:
        return 0
    return (x_max - x_min + 1) * (y_max - y_min + 1)


def percentile95(values):
    return sorted(values)[math.ceil(0.95 * len(values)) - 1]


def write_rows(output_path, data_dir):
    runs = {
        variant: parse_log(data_dir / f"triangle_regression_{variant}.log")
        for variant in VARIANTS
    }
    reference = runs["direct"]
    for variant in VARIANTS[1:]:
        for case_id in range(CORPUS_SIZE):
            if runs[variant][case_id][1] != reference[case_id][1]:
                raise ValueError(f"{variant}: inputs differ at case {case_id}")

    cases = []
    for case_id in range(CORPUS_SIZE):
        cycles = {variant: runs[variant][case_id][0] for variant in VARIANTS}
        vertices = reference[case_id][1]
        area = signed_area(vertices)
        if area == 0:
            expected_cycles = {variant: 0 for variant in VARIANTS}
        else:
            expected_cycles = {
                "direct": 256,
                "incremental": 256,
                "incremental_bbox": candidate_pixels(vertices),
            }
        for variant in VARIANTS:
            if cycles[variant] != expected_cycles[variant]:
                raise ValueError(
                    f"{variant}: case {case_id} took {cycles[variant]} cycles; "
                    f"expected {expected_cycles[variant]} from the scan model"
                )
        if area == 0:
            cohort = "degenerate"
        else:
            pixels = candidate_pixels(vertices)
            if pixels == 0:
                cohort = "nondegenerate_empty_bbox"
            elif pixels <= 16:
                cohort = "nondegenerate_bbox_1_16"
            elif pixels <= 64:
                cohort = "nondegenerate_bbox_17_64"
            else:
                cohort = "nondegenerate_bbox_65_plus"
        cases.append((cohort, cycles))

    cohorts = (
        "all",
        "nondegenerate",
        "degenerate",
        "nondegenerate_empty_bbox",
        "nondegenerate_bbox_1_16",
        "nondegenerate_bbox_17_64",
        "nondegenerate_bbox_65_plus",
    )
    with output_path.open("w", newline="") as destination:
        writer = csv.writer(destination)
        writer.writerow(
            (
                "cohort",
                "case_count",
                "D_mean_cycles",
                "D_median_cycles",
                "D_p95_cycles",
                "I_mean_cycles",
                "I_median_cycles",
                "I_p95_cycles",
                "IB_mean_cycles",
                "IB_median_cycles",
                "IB_p95_cycles",
            )
        )
        for cohort in cohorts:
            selected = [
                values
                for case_cohort, values in cases
                if cohort == "all"
                or case_cohort == cohort
                or (cohort == "nondegenerate" and case_cohort.startswith("nondegenerate"))
            ]
            if not selected:
                continue
            row = [cohort, len(selected)]
            for variant in VARIANTS:
                values = [entry[variant] for entry in selected]
                row.extend(
                    (
                        f"{statistics.mean(values):.2f}",
                        f"{statistics.median(values):.2f}",
                        percentile95(values),
                    )
                )
            writer.writerow(row)


def main():
    if len(sys.argv) != 3:
        raise SystemExit(
            "usage: summarize_triangle_corpus.py <report-data-dir> <output.csv>"
        )
    data_dir = Path(sys.argv[1])
    output_path = Path(sys.argv[2])
    write_rows(output_path, data_dir)


if __name__ == "__main__":
    main()
