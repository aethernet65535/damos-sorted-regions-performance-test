#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0

prog_description = '''
Generate masim config for testing DAMOS sorted regions with even/odd access pattern.

This mimics the behavior of access_memory_even.c from kselftest:
  - Even-indexed regions (0, 2, 4, ...) are HOT (accessed frequently)
  - Odd-indexed regions (1, 3, 5, ...) are COLD (never accessed)

This creates a clear cold/hot distinction, ideal for verifying that
DAMON with score_desc correctly identifies and pages out cold regions first.

The total runtime = nr_threads * (hot_time + idle_time)

Example:
  # 8 GiB system, 10 regions, 10 threads, 1 hour total
  python3 evenodd_test_config.py \\
      --memsize 8589934592 \\
      --nr_regions 10 \\
      --nr_threads 10 \\
      --hot_time 300000 \\
      --idle_time 60000

  # Each thread: 5min hot access + 1min idle = 6min cycle
  # 10 threads * 6min = 60min = 1 hour
'''

import argparse
import sys

import masim_config


def parse_bytes(text):
    suffix_unit = {
        'b': 1,
        'k': 1024,
        'm': 1024**2,
        'g': 1024**3,
        't': 1024**4,
    }
    suffix = text[-1].lower()
    if suffix in suffix_unit:
        numbers = text[:-1]
    else:
        numbers = text
    try:
        numbers = int(numbers)
    except Exception as e:
        return None, 'number parsing fail (%s)' % e

    if suffix in suffix_unit:
        numbers = numbers * suffix_unit[suffix]
    return numbers, None


def main():
    parser = argparse.ArgumentParser(
        description=prog_description,
        formatter_class=argparse.RawDescriptionHelpFormatter)

    parser.add_argument('--memsize', metavar='<bytes>', type=int,
                        help='total memory size (default: auto-calculate '
                             'from nr_regions * region_size)')
    parser.add_argument('--nr_regions', type=int, metavar='<number>',
                        default=10,
                        help='number of regions (default: 10)')
    parser.add_argument('--region_size', metavar='<bytes>', type=int,
                        default=None,
                        help='size of each region in bytes. If not set, '
                             'regions will be sized to fill memsize')
    parser.add_argument('--nr_threads', type=int, metavar='<number>',
                        default=10,
                        help='number of threads (default: 10)')
    parser.add_argument('--hot_time', metavar='<milliseconds>', type=int,
                        default=300000,
                        help='hot phase duration (default: 300000ms = 5min)')
    parser.add_argument('--idle_time', metavar='<milliseconds>', type=int,
                        default=60000,
                        help='idle phase duration between hot accesses '
                             '(default: 60000ms = 1min)')
    parser.add_argument('--rw_mode', choices=['ro', 'wo', 'rw'],
                        default='rw',
                        help='read/write mode (default: rw)')
    parser.add_argument('--randomness', type=int, choices=[0, 1],
                        default=0,
                        help='0=sequential, 1=random (default: 0)')
    parser.add_argument('--stride', metavar='<bytes>', type=int,
                        default=4096,
                        help='stride size for sequential access (default: 4096)')

    args = parser.parse_args()

    # Calculate region size
    if args.region_size is not None:
        region_size = args.region_size
        total_size = region_size * args.nr_regions
    elif args.memsize is not None:
        region_size = args.memsize // args.nr_regions
        total_size = region_size * args.nr_regions
    else:
        print('Error: either --memsize or --region_size must be specified',
              file=sys.stderr)
        exit(1)

    cycle_time = args.hot_time + args.idle_time
    total_time_ms = args.nr_threads * cycle_time
    total_time_s = total_time_ms / 1000

    # Count hot and cold regions
    nr_hot = (args.nr_regions + 1) // 2  # even indices: 0, 2, 4, ...
    nr_cold = args.nr_regions // 2        # odd indices: 1, 3, 5, ...

    print('# Even/Odd access pattern for DAMOS sorted regions testing', file=sys.stdout)
    print('# Hot regions (even): %d x %d bytes = %d GiB' % (
        nr_hot, region_size, (nr_hot * region_size) // (1024**3)), file=sys.stdout)
    print('# Cold regions (odd): %d x %d bytes = %d GiB' % (
        nr_cold, region_size, (nr_cold * region_size) // (1024**3)), file=sys.stdout)
    print('# Total: %d GiB, Threads: %d, Cycle: %ds, Total: %ds (%.1f hours)' % (
        total_size // (1024**3), args.nr_threads, cycle_time // 1000,
        total_time_s, total_time_s / 3600), file=sys.stdout)
    print('#', file=sys.stdout)

    # Create regions
    regions = []
    for i in range(args.nr_regions):
        regions.append(masim_config.Region(
            name='r%d' % i, sz_bytes=region_size, init_data_file=None))

    # Create phases
    # Each thread has two phases:
    # 1. hot phase: access all even regions
    # 2. idle phase: do nothing (access a tiny dummy region to keep masim running)
    phases = []
    for t in range(args.nr_threads):
        # Hot phase: access all even-indexed regions
        hot_patterns = []
        for i in range(0, args.nr_regions, 2):  # 0, 2, 4, ...
            hot_patterns.append(masim_config.AccessPattern(
                region_name='r%d' % i,
                randomness=bool(args.randomness),
                stride=args.stride,
                access_probability=100,
                rw_mode=args.rw_mode))
        phases.append(masim_config.Phase(
            name='hot phase %d' % t,
            runtime_ms=args.hot_time,
            patterns=hot_patterns))

        # Idle phase: access all regions with very low probability
        # This creates a "gap" in access time, making cold regions age
        idle_patterns = []
        for i in range(args.nr_regions):
            idle_patterns.append(masim_config.AccessPattern(
                region_name='r%d' % i,
                randomness=bool(args.randomness),
                stride=args.stride,
                access_probability=1,
                rw_mode='ro'))
        phases.append(masim_config.Phase(
            name='idle phase %d' % t,
            runtime_ms=args.idle_time,
            patterns=idle_patterns))

    masim_config.pr_config(regions, phases)


if __name__ == '__main__':
    main()
