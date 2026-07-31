#!/usr/bin/env python3
import sys
import os
import numpy as np

TIME_SERIES_FILES = ["cpu.txt", "fault.txt", "io.txt", "memo.txt", "memu.txt"]


def parse_time_series_file(filepath):
    with open(filepath, "r") as f:
        lines = f.readlines()

    if len(lines) < 4:
        return None, None

    header_line = lines[2].strip()
    headers = header_line.split()[1:]

    data_lines = []
    for line in lines[3:-1]:
        line = line.strip()
        if not line or line.startswith("Average:"):
            continue
        parts = line.split()
        try:
            row = [float(x) for x in parts[1:]]
            data_lines.append(row)
        except ValueError:
            continue

    if not data_lines:
        return headers, [0.0] * len(headers)

    arr = np.array(data_lines)
    p99_values = np.percentile(arr, 99, axis=0)
    return headers, p99_values


def main():
    dirs = sys.argv[1:] if len(sys.argv) > 1 else ["."]

    for d in dirs:
        dir_name = os.path.basename(os.path.abspath(d))
        print(f"=== P99 Report: {dir_name} ===\n")

        for fname in TIME_SERIES_FILES:
            fpath = os.path.join(d, fname)
            if not os.path.isfile(fpath):
                continue

            headers, p99_values = parse_time_series_file(fpath)
            if headers is None:
                continue

            print(f"File: {fname}")

            col_widths = [max(len(h), 12) for h in headers]

            header_str = "".join(h.rjust(w) for h, w in zip(headers, col_widths))
            print(f"  {header_str}")

            values_str = "".join(f"{v:>{w}.2f}" for v, w in zip(p99_values, col_widths))
            print(f"  {values_str}")
            print()

    return 0


if __name__ == "__main__":
    sys.exit(main())
