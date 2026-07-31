#!/bin/bash

# DAMOS SORTED REGIONS PERFORMANCE TEST - VANILLA
# ===============================================

# --- Configuration ---
MIN_SEC=60
HOUR_SEC=$((60 * MIN_SEC))

DIR_NAME="pageout-vanilla"
DATE="2026-07-31-0001"
REPORT_DIR="./report/${DIR_NAME}-${DATE}"

TEST_SECS=$((1 * HOUR_SEC))
INTERVAL_SECS=5
SAMPLING_TIMES=$((TEST_SECS / INTERVAL_SECS))

MASIM_PATH="../external/masim"

make -C $MASIM_PATH

MASIM_BIN="./masim"
MASIM_CFG="configs/sliding-window.cfg"

# --- Root Privileges Check ---
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: Please run as root." >&2
    exit 1
fi

# --- Initialization ---
pkill -x sar

rm -rf "$REPORT_DIR"
mkdir -p "$REPORT_DIR"

# --- Baseline Metrics (Before) ---
grep "refault" /proc/vmstat >> "$REPORT_DIR/refault.txt"
grep "pgsteal" /proc/vmstat >> "$REPORT_DIR/pgsteal.txt"

# --- Start Background Monitoring (SAR) ---
sar -r      $INTERVAL_SECS $SAMPLING_TIMES >> "$REPORT_DIR/memu.txt" &
sar -q CPU  $INTERVAL_SECS $SAMPLING_TIMES >> "$REPORT_DIR/cpu.txt" &
sar -q IO   $INTERVAL_SECS $SAMPLING_TIMES >> "$REPORT_DIR/io.txt" &
sar -q MEM  $INTERVAL_SECS $SAMPLING_TIMES >> "$REPORT_DIR/memo.txt" &
sar -B      $INTERVAL_SECS $SAMPLING_TIMES >> "$REPORT_DIR/fault.txt" &

# --- Test Execution ---
echo "Starting test workload..."
pushd $MASIM_PATH
$MASIM_BIN $MASIM_CFG
popd

# --- Stop Monitoring ---
pkill -INT -x sar

# --- Post-Test Metrics (After) ---
grep "refault" /proc/vmstat >> "$REPORT_DIR/refault.txt"
grep "pgsteal" /proc/vmstat >> "$REPORT_DIR/pgsteal.txt"

echo "Test completed successfully. Results saved in $REPORT_DIR"
