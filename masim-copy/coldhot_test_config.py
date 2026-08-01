#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0

prog_description = '''
Generate masim config for DAMOS sorted regions performance testing.

The configuration creates a cold/hot tiered workload with clear access frequency
differentiation.  This is ideal for testing DAMON sorted regions patch
(damos_sort_type=score_desc), which should correctly identify and page out
coldest regions first.

Key features:
  - Asymmetric region sizes: cold regions are larger, hot regions smaller
  - Explicit phase-based access: each phase accesses only ONE region at a time
  - Cycle-based design: cold -> warm -> hot phases form a cycle
  - Configurable number of threads for memory pressure control

Example:
  # 8 GiB system, 3 tiers, 10 threads, 1 hour total
  python3 coldhot_test_config.py \\
      --memsize 8589934592 \\
      --nr_threads 10 \\
      --cold_size 4294967296 \\
      --warm_size 2147483648 \\
      --hot_size 2147483648 \\
      --cold_time 36000 \\
      --warm_time 72000 \\
      --hot_time 252000

  Total runtime = nr_threads * (cold_time + warm_time + hot_time)
                = 10 * (36s + 72s + 252s) = 3600s = 1 hour
'''

import argparse

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
                        help='total memory size (ignored if individual '
                             'sizes are given)')
    parser.add_argument('--cold_size', metavar='<bytes>', type=int,
                        default=4294967296,
                        help='size of cold region (default: 4 GiB)')
    parser.add_argument('--warm_size', metavar='<bytes>', type=int,
                        default=2147483648,
                        help='size of warm region (default: 2 GiB)')
    parser.add_argument('--hot_size', metavar='<bytes>', type=int,
                        default=2147483648,
                        help='size of hot region (default: 2 GiB)')
    parser.add_argument('--nr_threads', type=int, metavar='<number>',
                        default=4,
                        help='number of threads (default: 4)')
    parser.add_argument('--cold_time', metavar='<milliseconds>', type=int,
                        default=90000,
                        help='cold phase duration (default: 90000ms = 90s)')
    parser.add_argument('--warm_time', metavar='<milliseconds>', type=int,
                        default=180000,
                        help='warm phase duration (default: 180000ms = 180s)')
    parser.add_argument('--hot_time', metavar='<milliseconds>', type=int,
                        default=630000,
                        help='hot phase duration (default: 630000ms = 630s)')
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

    cold_size = args.cold_size
    warm_size = args.warm_size
    hot_size = args.hot_size

    if args.memsize is not None:
        total = cold_size + warm_size + hot_size
        if total != args.memsize:
            print('Warning: cold_size + warm_size + hot_size = %d '
                  '!= memsize %d' % (total, args.memsize))

    cycle_time = args.cold_time + args.warm_time + args.hot_time
    total_time_ms = args.nr_threads * cycle_time
    total_time_s = total_time_ms / 1000
    total_size = cold_size + warm_size + hot_size

    print('# Cold/Hot tiered workload for DAMOS sorted regions testing',
          file=masim_config.sys.stdout if hasattr(masim_config, 'sys')
          else None)
    print('# Regions: cold=%d GiB, warm=%d GiB, hot=%d GiB, total=%d GiB'
          % (cold_size // (1024**3), warm_size // (1024**3),
             hot_size // (1024**3), total_size // (1024**3)),
          file=None)
    print('# Threads: %d, Cycle: %ds, Total: %ds (%.1f hours)'
          % (args.nr_threads, cycle_time // 1000,
             total_time_s, total_time_s / 3600),
          file=None)
    print('#', file=None)

    regions = [
        masim_config.Region('hot', hot_size, None),
        masim_config.Region('warm', warm_size, None),
        masim_config.Region('cold', cold_size, None),
    ]

    phases = []
    for t in range(args.nr_threads):
        # Cold phase: only cold region is accessed
        cold_patterns = [
            masim_config.AccessPattern(
                region_name='cold', randomness=bool(args.randomness),
                stride=args.stride, access_probability=100,
                rw_mode=args.rw_mode),
        ]
        phases.append(masim_config.Phase(
            name='cold phase %d' % t,
            runtime_ms=args.cold_time,
            patterns=cold_patterns))

        # Warm phase: only warm region is accessed
        warm_patterns = [
            masim_config.AccessPattern(
                region_name='warm', randomness=bool(args.randomness),
                stride=args.stride, access_probability=100,
                rw_mode=args.rw_mode),
        ]
        phases.append(masim_config.Phase(
            name='warm phase %d' % t,
            runtime_ms=args.warm_time,
            patterns=warm_patterns))

        # Hot phase: only hot region is accessed
        hot_patterns = [
            masim_config.AccessPattern(
                region_name='hot', randomness=bool(args.randomness),
                stride=args.stride, access_probability=100,
                rw_mode=args.rw_mode),
        ]
        phases.append(masim_config.Phase(
            name='hot phase %d' % t,
            runtime_ms=args.hot_time,
            patterns=hot_patterns))

    masim_config.pr_config(regions, phases)


if __name__ == '__main__':
    main()
