#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0

prog_description = '''
Generate masim config for testing DAMOS sorted regions with cloud-native workload.

This simulates a microservice environment with 4-tier cold/hot distribution:

  Tier    Name          Size      Access Pattern           Ratio
  ---------------------------------------------------------------
  L0      svc_code      800MB     High-freq read           Hot (60%)
  L0      session       1.2GiB    High-freq read/write     Hot (60%)
  L1      cache         1.6GiB    Mid-freq read            Warm (25%)
  L1      config        400MB     Low-freq read            Warm (25%)
  L2      temp          1.2GiB    Mid-freq write           Cold (12%)
  L2      logs          2.0GiB    High-freq write          Cold (12%)
  L3      archive       800MB     Very-low-freq            Frozen (3%)

Total memory: ~8 GiB
Cycle: 300s (5min) per thread
Threads: 12
Total runtime: 12 * 5min = 60min = 1 hour

This workload is ideal for testing sorted regions because:
  - Clear age gradient: hot regions stay hot, frozen regions age quickly
  - Asymmetric read/write patterns (logs write-heavy, cache read-heavy)
  - Realistic size distribution matching cloud deployments
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
                        default=8589934592,
                        help='total memory size (default: 8 GiB)')
    parser.add_argument('--nr_threads', type=int, metavar='<number>',
                        default=12,
                        help='number of threads (default: 12)')
    parser.add_argument('--cycle_time', metavar='<seconds>', type=int,
                        default=300,
                        help='cycle duration in seconds (default: 300s = 5min)')
    parser.add_argument('--rw_mode', choices=['ro', 'wo', 'rw'],
                        default='rw',
                        help='default read/write mode (default: rw)')
    parser.add_argument('--randomness', type=int, choices=[0, 1],
                        default=0,
                        help='0=sequential, 1=random (default: 0)')
    parser.add_argument('--stride', metavar='<bytes>', type=int,
                        default=4096,
                        help='stride size for sequential access (default: 4096)')

    args = parser.parse_args()

    memsize = args.memsize
    cycle_time_ms = args.cycle_time * 1000

    # Default region sizes (proportional to memsize)
    # Ratios: svc_code=10%, session=15%, cache=20%, config=5%, temp=15%, logs=25%, archive=10%
    ratios = {
        'svc_code': 0.10,
        'session': 0.15,
        'cache': 0.20,
        'config': 0.05,
        'temp': 0.15,
        'logs': 0.25,
        'archive': 0.10,
    }

    sizes = {}
    for name, ratio in ratios.items():
        sizes[name] = int(memsize * ratio)

    # Time allocation per cycle (proportional to cold/hot tier)
    # Hot tier: 60%, Warm tier: 25%, Cold tier: 12%, Frozen tier: 3%
    hot_time = int(cycle_time_ms * 0.60)
    warm_time = int(cycle_time_ms * 0.25)
    cold_time = int(cycle_time_ms * 0.12)
    frozen_time = cycle_time_ms - hot_time - warm_time - cold_time

    total_time_s = args.nr_threads * args.cycle_time
    total_hot = sizes['svc_code'] + sizes['session']
    total_warm = sizes['cache'] + sizes['config']
    total_cold = sizes['temp'] + sizes['logs']
    total_frozen = sizes['archive']

    # Print header comments
    print('# Cloud-Native Microservice Workload for DAMOS Sorted Regions Testing',
          file=sys.stdout)
    print('#', file=sys.stdout)
    print('# Region          Size        Tier    Access Pattern', file=sys.stdout)
    print('# ------------------------------------------------', file=sys.stdout)
    print('# svc_code    %6d MiB    L0      High-freq read (hot)' % (
        sizes['svc_code'] // (1024**2)), file=sys.stdout)
    print('# session     %6d MiB    L0      High-freq read/write (hot)' % (
        sizes['session'] // (1024**2)), file=sys.stdout)
    print('# cache       %6d MiB    L1      Mid-freq read (warm)' % (
        sizes['cache'] // (1024**2)), file=sys.stdout)
    print('# config      %6d MiB    L1      Low-freq read (warm)' % (
        sizes['config'] // (1024**2)), file=sys.stdout)
    print('# temp        %6d MiB    L2      Mid-freq write (cold)' % (
        sizes['temp'] // (1024**2)), file=sys.stdout)
    print('# logs        %6d MiB    L2      High-freq write (cold)' % (
        sizes['logs'] // (1024**2)), file=sys.stdout)
    print('# archive     %6d MiB    L3      Very-low-freq (frozen)' % (
        sizes['archive'] // (1024**2)), file=sys.stdout)
    print('#', file=sys.stdout)
    print('# Total: %d GiB, Threads: %d, Cycle: %ds, Total: %ds (%.1f hours)' % (
        memsize // (1024**3), args.nr_threads, args.cycle_time,
        total_time_s, total_time_s / 3600), file=sys.stdout)
    print('#', file=sys.stdout)

    # Create regions
    regions = [
        masim_config.Region('svc_code', sizes['svc_code'], None),
        masim_config.Region('session', sizes['session'], None),
        masim_config.Region('cache', sizes['cache'], None),
        masim_config.Region('config', sizes['config'], None),
        masim_config.Region('temp', sizes['temp'], None),
        masim_config.Region('logs', sizes['logs'], None),
        masim_config.Region('archive', sizes['archive'], None),
    ]

    # Create phases for each thread
    phases = []
    for t in range(args.nr_threads):
        # Phase 1: Hot tier (60%) - service code + session
        hot_patterns = [
            masim_config.AccessPattern(
                region_name='svc_code',
                randomness=bool(args.randomness),
                stride=args.stride,
                access_probability=40,
                rw_mode='ro'),
            masim_config.AccessPattern(
                region_name='session',
                randomness=bool(args.randomness),
                stride=args.stride,
                access_probability=60,
                rw_mode='rw'),
        ]
        phases.append(masim_config.Phase(
            name='hot phase %d' % t,
            runtime_ms=hot_time,
            patterns=hot_patterns))

        # Phase 2: Warm tier (25%) - cache + config
        warm_patterns = [
            masim_config.AccessPattern(
                region_name='cache',
                randomness=bool(args.randomness),
                stride=args.stride,
                access_probability=80,
                rw_mode='ro'),
            masim_config.AccessPattern(
                region_name='config',
                randomness=bool(args.randomness),
                stride=args.stride,
                access_probability=20,
                rw_mode='ro'),
        ]
        phases.append(masim_config.Phase(
            name='warm phase %d' % t,
            runtime_ms=warm_time,
            patterns=warm_patterns))

        # Phase 3: Cold tier (12%) - temp + logs
        cold_patterns = [
            masim_config.AccessPattern(
                region_name='temp',
                randomness=bool(args.randomness),
                stride=args.stride,
                access_probability=30,
                rw_mode='wo'),
            masim_config.AccessPattern(
                region_name='logs',
                randomness=bool(args.randomness),
                stride=args.stride,
                access_probability=70,
                rw_mode='wo'),
        ]
        phases.append(masim_config.Phase(
            name='cold phase %d' % t,
            runtime_ms=cold_time,
            patterns=cold_patterns))

        # Phase 4: Frozen tier (3%) - archive
        frozen_patterns = [
            masim_config.AccessPattern(
                region_name='archive',
                randomness=bool(args.randomness),
                stride=args.stride,
                access_probability=100,
                rw_mode='ro'),
        ]
        phases.append(masim_config.Phase(
            name='frozen phase %d' % t,
            runtime_ms=frozen_time,
            patterns=frozen_patterns))

    masim_config.pr_config(regions, phases)


if __name__ == '__main__':
    main()
