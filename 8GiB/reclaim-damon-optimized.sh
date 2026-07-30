#!/bin/bash

# DAMOS SORTED REGIONS PERFORMANCE TEST - DAMON OPTIMIZED
# =======================================================

# --- Configuration ---
MIN_SEC=60
HOUR_SEC=$((60 * MIN_SEC))

DIR_NAME="pageout-damon-optimized"
DATE="2026-07-30-0001"
REPORT_DIR="./report/${DIR_NAME}-${DATE}"

TEST_SECS=$((1 * HOUR_SEC))
INTERVAL_SECS=5
SAMPLING_TIMES=$((TEST_SECS / INTERVAL_SECS))

ADMIN="/sys/kernel/mm/damon/admin"
STATS="$ADMIN/kdamonds/0/contexts/0/schemes/0/stats"
SCHEME=$ADMIN/kdamonds/0/contexts/0/schemes/0

MASIM_PATH="../external/masim"

make -C $MASIM_PATH

MASIM_BIN="../external/masim/masim"
MASIM_CFG="../external/masim/configs/sliding-window.cfg"

# --- Root Privileges Check ---
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: Please run as root." >&2
    exit 1
fi

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
pkill -x sar

./enable-damos-pageout.sh

rm -rf "$REPORT_DIR"
mkdir -p "$REPORT_DIR"

# --- Baseline Metrics (Before) ---
grep "refault" /proc/vmstat >> "$REPORT_DIR/refault.txt"
grep "pgsteal" /proc/vmstat >> "$REPORT_DIR/pgsteal.txt"

echo "update_schemes_stats" > "$ADMIN/kdamonds/0/state"
log_damon_stats "Before"

# --- Start Background Monitoring (SAR) ---
sar -r      $INTERVAL_SECS $SAMPLING_TIMES >> "$REPORT_DIR/memu.txt" &
sar -q CPU  $INTERVAL_SECS $SAMPLING_TIMES >> "$REPORT_DIR/cpu.txt" &
sar -q IO   $INTERVAL_SECS $SAMPLING_TIMES >> "$REPORT_DIR/io.txt" &
sar -q MEM  $INTERVAL_SECS $SAMPLING_TIMES >> "$REPORT_DIR/memo.txt" &
sar -B      $INTERVAL_SECS $SAMPLING_TIMES >> "$REPORT_DIR/fault.txt" &

# --- Test Execution ---
echo "Starting test workload..."
"$MASIM_BIN" "$MASIM_CFG" &
echo score_desc > $SCHEME/sort_type
echo $(pidof masim) > $ADMIN/kdamonds/0/contexts/0/targets/0/pid_target
echo on > $ADMIN/kdamonds/0/state

sleep 60m

# --- Stop Monitoring ---
pkill -INT -x sar

# --- Post-Test Metrics (After) ---
grep "refault" /proc/vmstat >> "$REPORT_DIR/refault.txt"
grep "pgsteal" /proc/vmstat >> "$REPORT_DIR/pgsteal.txt"

log_damon_stats "After"

echo "Test completed successfully. Results saved in $REPORT_DIR"
