from masim_config import Region, AccessPattern, Phase, pr_config

KiB = 1 * 1024
MiB = 1024 * KiB
GiB = 1024 * MiB

SEC_MS = 1000
MIN_MS = 60 * SEC_MS

PAGE_SIZE = 4096
TOTAL_MEM = 8 * GiB
TOTAL_TEST_TIME = 60 * MIN_MS
PHASE_RUNTIME = 10 * MIN_MS

regions = [
    Region('region_hot', int(TOTAL_MEM * 0.2), 'none'),
    Region('region_warm', int(TOTAL_MEM * 0.3), 'none'),
    Region('region_cold', int(TOTAL_MEM * 0.5), 'none'),
]

phases = [
    Phase('phase1', PHASE_RUNTIME, [
        AccessPattern('region_hot', False, PAGE_SIZE, 70, 'rw'),
        AccessPattern('region_warm', False, PAGE_SIZE, 20, 'rw'),
        AccessPattern('region_cold', False, PAGE_SIZE, 10, 'rw'),
    ]),
    Phase('phase2', PHASE_RUNTIME, [
        AccessPattern('region_hot', False, PAGE_SIZE, 30, 'rw'),
        AccessPattern('region_warm', False, PAGE_SIZE, 50, 'rw'),
        AccessPattern('region_cold', False, PAGE_SIZE, 20, 'rw'),
    ]),
    Phase('phase3', PHASE_RUNTIME, [
        AccessPattern('region_hot', False, PAGE_SIZE, 20, 'rw'),
        AccessPattern('region_warm', False, PAGE_SIZE, 30, 'rw'),
        AccessPattern('region_cold', False, PAGE_SIZE, 50, 'rw'),
    ]),
    Phase('phase4', PHASE_RUNTIME, [
        AccessPattern('region_hot', False, PAGE_SIZE, 50, 'rw'),
        AccessPattern('region_warm', False, PAGE_SIZE, 17, 'rw'),
        AccessPattern('region_cold', False, PAGE_SIZE, 11, 'rw'),
    ]),
    Phase('phase5', PHASE_RUNTIME, [
        AccessPattern('region_hot', False, PAGE_SIZE, 60, 'rw'),
        AccessPattern('region_warm', False, PAGE_SIZE, 25, 'rw'),
        AccessPattern('region_cold', False, PAGE_SIZE, 15, 'rw'),
    ]),
    Phase('phase6', PHASE_RUNTIME, [
        AccessPattern('region_hot', False, PAGE_SIZE, 40, 'rw'),
        AccessPattern('region_warm', False, PAGE_SIZE, 35, 'rw'),
        AccessPattern('region_cold', False, PAGE_SIZE, 25, 'rw'),
    ]),
]

pr_config(regions, phases)
