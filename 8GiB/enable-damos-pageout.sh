#!/bin/bash
ADMIN=/sys/kernel/mm/damon/admin

if [ "$(id -u)" -ne 0 ]; then
  echo "please run as root"
  exit 1
fi

# Create one kdamond with one context
echo 1 > $ADMIN/kdamonds/nr_kdamonds
echo 1 > $ADMIN/kdamonds/0/contexts/nr_contexts

# Use the virtual address space ops
echo vaddr > $ADMIN/kdamonds/0/contexts/0/operations

# Tune monitoring intervals
echo 5000   > $ADMIN/kdamonds/0/contexts/0/monitoring_attrs/intervals/sample_us
echo 100000 > $ADMIN/kdamonds/0/contexts/0/monitoring_attrs/intervals/aggr_us

# One target (paddr needs exactly one target; no pid_target needed)
echo 1 > $ADMIN/kdamonds/0/contexts/0/targets/nr_targets

# Create one DAMOS scheme
echo 1 > $ADMIN/kdamonds/0/contexts/0/schemes/nr_schemes
SCHEME=$ADMIN/kdamonds/0/contexts/0/schemes/0

# Action: page out
echo pageout > $SCHEME/action

# Access pattern: size [4KB, unlimited], nr_accesses [0,0], age [24000,max]
# age 24000 = 24000 aggr intervals × 100ms = 2,400,000ms ≈ 2400s ... too long
# Better: age in aggr intervals. 120s / 100ms = 1200 aggregation intervals
echo 4096           > $SCHEME/access_pattern/sz/min
echo 18446744073709551615 > $SCHEME/access_pattern/sz/max
echo 0              > $SCHEME/access_pattern/nr_accesses/min
echo 0              > $SCHEME/access_pattern/nr_accesses/max
echo 1200           > $SCHEME/access_pattern/age/min
echo 18446744073709551615 > $SCHEME/access_pattern/age/max

# Quota: use at most 10ms CPU, page out at most 128MiB per second
echo 10            > $SCHEME/quotas/ms
echo 134217728     > $SCHEME/quotas/bytes       # 128 MiB
echo 1000          > $SCHEME/quotas/reset_interval_ms
# Prioritize older (colder) regions first
echo 0 > $SCHEME/quotas/weights/sz_permil
echo 0 > $SCHEME/quotas/weights/nr_accesses_permil
echo 1000 > $SCHEME/quotas/weights/age_permil

# Watermarks: only activate when free memory is lower than 50%/40%.
echo free_mem_rate > $SCHEME/watermarks/metric
echo 5000000       > $SCHEME/watermarks/interval_us    # check every 5s
echo 500           > $SCHEME/watermarks/high           # deactivate above 50%
echo 400           > $SCHEME/watermarks/mid            # activate at 40%
echo 0             > $SCHEME/watermarks/low            # do not deactivate when memory pressure
