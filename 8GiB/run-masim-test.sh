#!/bin/bash

# DAMOS SORTED REGIONS PERFORMANCE TEST - MASIM WORKLOAD
# =======================================================
# Complete test script integrating masim workload + DAMON + SAR monitoring.
#
# Usage: ./run-masim-test.sh [options] [vanilla|damon|damon-optimized]
#   Options:
#     -g, --generate    Generate masim config using coldhot_test_config.py
#     -c, --config FILE Use specified masim config file
#   Modes:
#     vanilla        - No DAMON (baseline)
#     damon          - DAMON with default region order
#     damon-optimized - DAMON with sorted regions (score_desc) [default]
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

# masim configuration
MASIM_BIN="./masim-copy/masim"
MASIM_CONFIG="./masim-copy/configs/coldhot-8gib.cfg"
MASIM_GENERATOR="./masim-copy/coldhot_test_config.py"
MASIM_REPEAT=1
GENERATE_CONFIG=0

# DAMON paths
ADMIN="/sys/kernel/mm/damon/admin"
STATS="$ADMIN/kdamonds/0/contexts/0/schemes/0/stats"
SCHEME=$ADMIN/kdamonds/0/contexts/0/schemes/0

# --- Parse Options ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -g|--generate)
            GENERATE_CONFIG=1
            shift
            ;;
        -c|--config)
            MASIM_CONFIG="$2"
            shift 2
            ;;
        *)
            TEST_MODE="$1"
            shift
            ;;
    esac
done
TEST_MODE="${TEST_MODE:-damon-optimized}"

# Report directory
case "$TEST_MODE" in
    vanilla)
        DIR_NAME="masim-vanilla"
        ;;
    damon)
        DIR_NAME="masim-damon"
        ;;
    damon-optimized)
        DIR_NAME="masim-damon-optimized"
        ;;
    *)
        echo "Usage: $0 [vanilla|damon|damon-optimized]" >&2
        exit 1
        ;;
esac

DATE=$(date +%Y-%m-%d-%H%M)
REPORT_DIR="./report/${DIR_NAME}-${DATE}"

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
pkill -x sar 2>/dev/null
pkill -x masim 2>/dev/null

rm -rf "$REPORT_DIR"
mkdir -p "$REPORT_DIR"

echo "=== DAMOS Sorted Regions Performance Test ==="
echo "Mode:     $TEST_MODE"
echo "Duration: ${TEST_SECS}s (1 hour)"
echo "Report:   $REPORT_DIR"
echo ""

# --- ZRAM Setup ---
echo "[1/6] Setting up ZRAM..."
modprobe zram
echo 4096M > /sys/block/zram0/disksize
mkswap /dev/zram0
swapon /dev/zram0

# --- Compile masim ---
echo "[2/6] Checking masim binary..."
if [ ! -x "$MASIM_BIN" ]; then
    echo "  Compiling masim..."
    make -C "$(dirname "$MASIM_BIN")" -s
    if [ $? -ne 0 ]; then
        echo "Error: Failed to compile masim." >&2
        exit 1
    fi
fi
echo "  masim binary ready: $MASIM_BIN"

# --- Generate masim config if requested ---
if [ "$GENERATE_CONFIG" -eq 1 ]; then
    echo "  Generating masim config using $MASIM_GENERATOR..."
    python3 "$MASIM_GENERATOR" > "$MASIM_CONFIG"
    echo "  Config written to: $MASIM_CONFIG"
fi

# --- Setup DAMON ---
echo "[3/6] Configuring DAMON..."
if [ "$TEST_MODE" != "vanilla" ]; then
    ./enable-damos-pageout.sh
    echo "  DAMON enabled with pageout scheme."

    if [ "$TEST_MODE" = "damon-optimized" ]; then
        echo score_desc > "$SCHEME/sort_type"
        echo "  sort_type = score_desc (sorted regions enabled)"
    else
        echo "  sort_type = none (default region order)"
    fi
else
    echo "  DAMON disabled (vanilla mode)"
fi

# --- Baseline Metrics (Before) ---
echo "[4/6] Recording baseline metrics..."
grep "refault" /proc/vmstat >> "$REPORT_DIR/refault.txt"
grep "pgsteal" /proc/vmstat >> "$REPORT_DIR/pgsteal.txt"

if [ "$TEST_MODE" != "vanilla" ]; then
    log_damon_stats "Before"
fi

# --- Start masim Workload ---
echo "[5/6] Starting masim workload (12 phases x ~5min avg = 1hour)..."
"$MASIM_BIN" "$MASIM_CONFIG" --repeat="$MASIM_REPEAT" --quiet &
MASIM_PID=$!
echo "  masim PID: $MASIM_PID"

# --- Start Background Monitoring (SAR) ---
echo "[6/6] Starting SAR monitoring (every ${INTERVAL_SECS}s, ${SAMPLING_TIMES} samples)..."
sar -r      "$INTERVAL_SECS" "$SAMPLING_TIMES" >> "$REPORT_DIR/memu.txt" &
sar -q CPU  "$INTERVAL_SECS" "$SAMPLING_TIMES" >> "$REPORT_DIR/cpu.txt" &
sar -q IO   "$INTERVAL_SECS" "$SAMPLING_TIMES" >> "$REPORT_DIR/io.txt" &
sar -q MEM  "$INTERVAL_SECS" "$SAMPLING_TIMES" >> "$REPORT_DIR/memo.txt" &
sar -B      "$INTERVAL_SECS" "$SAMPLING_TIMES" >> "$REPORT_DIR/fault.txt" &

# --- Wait for masim to Finish ---
echo ""
echo "Test running. Waiting for masim to complete (PID: $MASIM_PID)..."
echo "  To check progress: ps -p $MASIM_PID -o pid,etime,pcpu,rss"
echo ""
wait $MASIM_PID
MASIM_EXIT=$?

# --- Stop Monitoring ---
pkill -INT -x sar 2>/dev/null
sleep 1

# --- Post-Test Metrics (After) ---
echo "Collecting post-test metrics..."
grep "refault" /proc/vmstat >> "$REPORT_DIR/refault.txt"
grep "pgsteal" /proc/vmstat >> "$REPORT_DIR/pgsteal.txt"

if [ "$TEST_MODE" != "vanilla" ]; then
    echo update_schemes_stats > "$ADMIN/kdamonds/0/state"
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

if [ $MASIM_EXIT -ne 0 ]; then
    echo "Warning: masim exited with code $MASIM_EXIT" >&2
fi

echo "To analyze results, run: python3 calc_p99.py $REPORT_DIR"
