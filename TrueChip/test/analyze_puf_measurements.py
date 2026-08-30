#!/usr/bin/env python3
"""Analyze RO-PUF IDs recorded in puf_measurements.csv.

CSV columns: board,repeat,puf_id,temp_c,vcc_v,reset_type
The puf_id column must contain exactly 32 hexadecimal characters.
"""
from __future__ import annotations

import argparse
import csv
from itertools import combinations
from pathlib import Path


def hd(a: int, b: int) -> int:
    return (a ^ b).bit_count()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("csv_file", nargs="?", default="puf_measurements.csv")
    args = ap.parse_args()

    groups: dict[str, list[int]] = {}
    with Path(args.csv_file).open(newline="", encoding="utf-8-sig") as fh:
        for line, row in enumerate(csv.DictReader(fh), start=2):
            board = (row.get("board") or "").strip()
            raw = (row.get("puf_id") or "").strip().lower().removeprefix("0x")
            if not board or len(raw) != 32:
                raise ValueError(f"line {line}: board/puf_id invalid; puf_id needs 32 hex chars")
            try:
                value = int(raw, 16)
            except ValueError as exc:
                raise ValueError(f"line {line}: puf_id is not hexadecimal") from exc
            groups.setdefault(board, []).append(value)

    if len(groups) < 2:
        raise ValueError("At least two boards are required for inter-device Hamming distance")

    print("=== TRUECHIP RO-PUF MEASUREMENT SUMMARY ===")
    refs: dict[str, int] = {}
    for board, values in sorted(groups.items()):
        refs[board] = values[0]
        intra = [hd(values[0], value) for value in values[1:]]
        mean_intra = sum(intra) / len(intra) if intra else 0.0
        reliability = 1.0 - mean_intra / 128.0
        uniformity = sum(value.bit_count() for value in values) / (128 * len(values))
        unstable = sum(
            any(((value >> bit) & 1) != ((values[0] >> bit) & 1) for value in values[1:])
            for bit in range(128)
        ) / 128.0
        print(
            f"board={board} samples={len(values)} reference={values[0]:032X} "
            f"intra_HD={mean_intra:.3f}/128 reliability={reliability:.5f} "
            f"uniformity={uniformity:.5f} unstable_bits={unstable:.5f}"
        )

    print("--- inter-device ---")
    all_inter = []
    for left, right in combinations(sorted(groups), 2):
        pair = [hd(a, b) for a in groups[left] for b in groups[right]]
        mean_pair = sum(pair) / len(pair)
        all_inter.extend(pair)
        print(f"{left} vs {right}: HD={mean_pair:.3f}/128 normalized={mean_pair / 128.0:.5f}")
    mean_inter = sum(all_inter) / len(all_inter)
    print(f"overall inter-device HD={mean_inter:.3f}/128 normalized={mean_inter / 128.0:.5f}")
    print("Reference only: normalized inter-device HD near 0.5 is desirable; two boards are limited evidence.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
