#!/bin/bash

# DAMOS SORTED REGIONS PERFORMANCE TEST - MASIM WORKLOAD
# =======================================================
# Complete test script integrated workload + DAMON + SAR monitoring.
#
# Prerequisites:
#   - Linux kernel with DAMON support
#   - Root privileges
#   - sar (sysstat) installed

# --- Configuration ---
MIN_SEC=60
HOUR_SEC=$((60 * MIN_SEC))

TEST_SECS=$((1 * HOUR_SEC))
INTERVAL_SECS=5
SAMPLING_TIMES=$((TEST_SECS / INTERVAL_SECS))

# DAMON paths
ADMIN="/sys/kernel/mm/damon/admin"
STATS="$ADMIN/kdamonds/0/contexts/0/schemes/0/stats"
SCHEME="$ADMIN/kdamonds/0/contexts/0/schemes/0"

# --- Root Privileges Check ---
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: Please run as root." >&2
    exit 1
fi

# --- Parse Options ---
if [[ $# -gt 0 ]]; then
    TEST_MODE="$1"
    shift
fi

TEST_MODE="${TEST_MODE:-damon-optimized}"

# Report directory
case "$TEST_MODE" in
    vanilla)
        DIR_NAME="vanilla"
        ;;
    damon)
        DIR_NAME="damon"
        ;;
    damon-optimized)
        DIR_NAME="damon-optimized"
        ;;
    *)
        echo "Usage: $0 [vanilla | damon | damon-optimized]" >&2
        exit 1
        ;;
esac

DATE=$(date +%Y-%m-%d-%H%M)
REPORT_DIR="./report/${DIR_NAME}-${DATE}"

# --- Helper Function for DAMON Stats ---
log_damon_stats() {
    local label="$1"
    {
        echo "--- $label ---"
        echo "Regions tried:   $(cat "$STATS/nr_tried")"
        echo "Bytes tried:     $(cat "$STATS/sz_tried")"
        echo "Regions applied: $(cat "$STATS/nr_applied")"
        echo "Bytes applied:   $(cat "$STATS/sz_applied")"
        echo "Quota exceeded:  $(cat "$STATS/qt_exceeds")"
        echo ""
    } >> "$REPORT_DIR/damon_stats.txt"
}

# --- Initialization ---
pkill -x sar 2>/dev/null

rm -rf "$REPORT_DIR"
mkdir -p "$REPORT_DIR"

echo "=== DAMOS Sorted Regions Performance Test ==="
echo "Mode:     $TEST_MODE"
echo "Duration: ${TEST_SECS}s (1 hour)"
echo "Report:   $REPORT_DIR"
echo ""

# --- ZRAM Setup ---
echo "[1/4] Setting up ZRAM..."
modprobe zram
echo 4096M > /sys/block/zram0/disksize
mkswap /dev/zram0
swapon /dev/zram0

# --- Setup DAMON ---
echo "[2/4] Configuring DAMON..."
if [ "$TEST_MODE" != "vanilla" ]; then
    ./apply-damon-reclaim.sh
    echo "  DAMON enabled with damon-reclaim config"

    echo 0          > $SCHEME/watermarks/low
    echo paddr      > $ADMIN/kdamonds/0/contexts/0/operations

    if [ "$TEST_MODE" = "damon-optimized" ]; then
        echo score_desc > $SCHEME/sort_type
        echo "  sort_type = score_desc (sorted regions enabled)"
    else
        echo "  sort_type = none (default region order)"
    fi
    echo on         > $ADMIN/kdamonds/0/state
    echo "  DAMON enabled"
else
    echo "  DAMON disabled (vanilla mode)"
fi

# --- Baseline Metrics (Before) ---
echo "[3/4] Recording baseline metrics..."
grep "refault" /proc/vmstat >> "$REPORT_DIR/refault.txt"
grep "pgsteal" /proc/vmstat >> "$REPORT_DIR/pgsteal.txt"

if [ "$TEST_MODE" != "vanilla" ]; then
    log_damon_stats "Before"
fi

# --- Start Background Monitoring (SAR) ---
echo "[4/6] Starting SAR monitoring (every ${INTERVAL_SECS}s, ${SAMPLING_TIMES} samples)..."
sar -r      "$INTERVAL_SECS" "$SAMPLING_TIMES" >> "$REPORT_DIR/memu.txt" &
sar -q CPU  "$INTERVAL_SECS" "$SAMPLING_TIMES" >> "$REPORT_DIR/cpu.txt" &
sar -q IO   "$INTERVAL_SECS" "$SAMPLING_TIMES" >> "$REPORT_DIR/io.txt" &
sar -q MEM  "$INTERVAL_SECS" "$SAMPLING_TIMES" >> "$REPORT_DIR/memo.txt" &
sar -B      "$INTERVAL_SECS" "$SAMPLING_TIMES" >> "$REPORT_DIR/fault.txt" &

# --- Workload ---
echo "[4/4] Start stress-ng workload..."

# L3 Frozen
stress-ng --vm 1 --vm-keep --vm-bytes 2G    --vm-hang 480   --timeout=3600s & sleep 10

# L2 Cold
stress-ng --vm 1 --vm-keep --vm-bytes 1G    --vm-hang 240   --timeout=3590s & sleep 10
stress-ng --vm 1 --vm-keep --vm-bytes 1G    --vm-hang 120   --timeout=3580s & sleep 10

# L1 Cold
stress-ng --vm 1 --vm-keep --vm-bytes 1G    --vm-hang 60    --timeout=3570s & sleep 10
stress-ng --vm 1 --vm-keep --vm-bytes 1G    --vm-hang 30    --timeout=3560s & sleep 10

# L0 Hot
stress-ng --vm 1 --vm-keep --vm-bytes 2G    --vm-hang 1     --timeout=3550s & sleep 10

# --- Wait for stress-ng to finish
echo ""
echo "Test running..."
sleep 3540s
echo "DONE!"

# --- Stop Monitoring ---
pkill -INT -x sar 2>/dev/null
sleep 1

# --- Post-Test Metrics (After) ---
echo "Collecting post-test metrics..."
grep "refault" /proc/vmstat >> "$REPORT_DIR/refault.txt"
grep "pgsteal" /proc/vmstat >> "$REPORT_DIR/pgsteal.txt"

if [ "$TEST_MODE" != "vanilla" ]; then
    echo update_schemes_stats > "$ADMIN/kdamonds/0/state"
    sleep 10
    log_damon_stats "After"
fi

# --- Summary ---
echo ""
echo "=== Test Complete ==="
echo "Mode:   $TEST_MODE"
echo "Report: $REPORT_DIR"
echo "Files:"
ls -1 "$REPORT_DIR/"
echo ""

echo "To analyze results, run: python3 calc_p99.py $REPORT_DIR"
