#!/bin/bash

# DAMOS Sorted Regions Performance Test - Virtme-ng Automation
# =============================================================
# Automatically runs three test modes (vanilla, damon, damon-optimized)
# in separate Virtme-ng sessions.
#
# Usage: ./run-virtme-test.sh [options]
#   Options:
#     -k, --kernel PATH   Path to kernel directory
#                         (default: ~/65535/workspace/oss/linux/kernel/linux_mainline)
#     -c, --config FILE   Use specified masim config file
#     -g, --generate      Generate masim config using coldhot_test_config.py
#     -s, --skip MODE     Skip a test mode (can be used multiple times)
#                         e.g., -s vanilla -s damon
#     --dry-run           Show what would be done without executing
#     -h, --help          Show this help message
#
# This script:
#   1. Starts Virtme-ng with the specified kernel
#   2. Executes the test inside the VM
#   3. Exits Virtme-ng
#   4. Repeats for each test mode
#
# Results are saved in:
#   <project_dir>/8GiB/report/masim-{vanilla,damon,damon-optimized}-<date>/

set -e

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KERNEL_DIR="/home/user/65535/workspace/oss/linux/kernel/linux_mainline"
TEST_SCRIPT="$SCRIPT_DIR/8GiB/run-masim-test.sh"
MASIM_CONFIG=""
GENERATE_CONFIG=0
DRY_RUN=0
SKIP_MODES=()

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Helper Functions ---
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# --- Parse Options ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -k|--kernel)
            KERNEL_DIR="$2"
            shift 2
            ;;
        -c|--config)
            MASIM_CONFIG="$2"
            shift 2
            ;;
        -g|--generate)
            GENERATE_CONFIG=1
            shift
            ;;
        -s|--skip)
            SKIP_MODES+=("$2")
            shift 2
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        -h|--help)
            head -25 "$0" | grep "^#" | sed 's/^# \?//'
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# --- Check Prerequisites ---
log_info "Checking prerequisites..."

if [ ! -d "$KERNEL_DIR" ]; then
    log_error "Kernel directory not found: $KERNEL_DIR"
    log_error "Use -k/--kernel to specify the correct path"
    exit 1
fi

if [ ! -f "$TEST_SCRIPT" ]; then
    log_error "Test script not found: $TEST_SCRIPT"
    exit 1
fi

if ! command -v vng &> /dev/null; then
    log_error "virtme-ng (vng) not found in PATH"
    log_error "Install with: pip install virtme-ng"
    exit 1
fi

log_success "Prerequisites OK"

# --- Check if mode should be skipped ---
is_skipped() {
    local mode="$1"
    for skip in "${SKIP_MODES[@]}"; do
        if [ "$skip" = "$mode" ]; then
            return 0
        fi
    done
    return 1
}

# --- Run Test Mode ---
run_test() {
    local mode="$1"
    local mode_name="$2"

    if is_skipped "$mode"; then
        log_warn "Skipping $mode_name mode"
        return 0
    fi

    log_info "Starting $mode_name test..."

    # Build the command to execute inside VM
    local inner_cmd="cd $SCRIPT_DIR && bash 8GiB/run-masim-test.sh"

    if [ "$GENERATE_CONFIG" -eq 1 ]; then
        inner_cmd="$inner_cmd -g"
    fi

    if [ -n "$MASIM_CONFIG" ]; then
        inner_cmd="$inner_cmd -c $MASIM_CONFIG"
    fi

    inner_cmd="$inner_cmd $mode"

    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[DRY RUN] Would execute:"
        echo "  cd $KERNEL_DIR"
        echo "  vng --run . --rw --memory=8G --cpus=4 --rwdir $SCRIPT_DIR --exec \"$inner_cmd\""
        echo ""
        return 0
    fi

    # Start virtme-ng with the kernel and execute test
    log_info "Booting Virtme-ng..."
    (
        cd "$KERNEL_DIR"
        vng --run . --rw --memory=8G --cpus=4 --rwdir "$SCRIPT_DIR" --exec "$inner_cmd"
    )

    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        log_success "$mode_name test completed successfully"
    else
        log_error "$mode_name test failed with exit code $exit_code"
    fi

    echo ""
    return $exit_code
}

# --- Main ---
echo ""
echo "=========================================="
echo " DAMOS Sorted Regions Performance Test"
echo " Virtme-ng Automation"
echo "=========================================="
echo ""
log_info "Kernel:   $KERNEL_DIR"
log_info "Project:  $SCRIPT_DIR"
log_info "Skip:     ${SKIP_MODES[*]:-none}"
echo ""

# Record start time
START_TIME=$(date +%s)

# Run tests in sequence
TESTS=(
    "vanilla:Vanilla (No DAMON)"
    "damon:DAMON (Default)"
    "damon-optimized:DAMON Optimized (score_desc)"
)

FAILED_TESTS=()

for test in "${TESTS[@]}"; do
    IFS=':' read -r mode name <<< "$test"

    if ! run_test "$mode" "$name"; then
        FAILED_TESTS+=("$name")
    fi
done

# Record end time
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
DURATION_MIN=$((DURATION / 60))
DURATION_SEC=$((DURATION % 60))

# Summary
echo ""
echo "=========================================="
echo " Test Summary"
echo "=========================================="
echo ""
log_info "Total duration: ${DURATION_MIN}m ${DURATION_SEC}s"

if [ ${#FAILED_TESTS[@]} -eq 0 ]; then
    log_success "All tests completed successfully!"
else
    log_error "Failed tests:"
    for test in "${FAILED_TESTS[@]}"; do
        echo "  - $test"
    done
fi

echo ""
log_info "Results saved in: $SCRIPT_DIR/8GiB/report/"
ls -1 "$SCRIPT_DIR/8GiB/report/" 2>/dev/null | grep "^masim-" | while read dir; do
    echo "  - $dir"
done

echo ""
log_info "To analyze results, run:"
echo "  python3 $SCRIPT_DIR/calc_p99.py $SCRIPT_DIR/8GiB/report/<result_dir>"
echo ""

if [ "$DRY_RUN" -eq 1 ]; then
    log_warn "This was a dry run. No tests were actually executed."
fi
