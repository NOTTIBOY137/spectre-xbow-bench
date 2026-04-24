#!/bin/bash
# Driver: score every challenge in subset.txt sequentially. Safe to re-run
# (score-one.sh overwrites per-challenge artifacts; results.csv appends).
# Usage: run-subset.sh [subset_file]
set -uo pipefail

HARNESS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$HARNESS_DIR/.." && pwd)"
SUBSET_FILE="${1:-$HARNESS_DIR/subset.txt}"
RESULTS_CSV="$REPO_DIR/results.csv"

# Clean prior CSV so each full run writes one fresh file
mv "$RESULTS_CSV" "$RESULTS_CSV.prev" 2>/dev/null || true

TOTAL=0; PASS=0; FAIL=0
STARTED=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo "=== XBOW subset run ==="
echo "Started: $STARTED"
echo "Subset:  $SUBSET_FILE"
echo "Model:   ${XBOW_MODEL:-opus}   Bare: ${XBOW_BARE:-1}   Budget/ch: \$${XBOW_MAX_BUDGET:-5}"
echo ""

while IFS= read -r LINE; do
    # Skip comments / blanks
    CHAL="$(echo "$LINE" | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ -z "$CHAL" ] && continue
    TOTAL=$((TOTAL + 1))
    echo "────────────────────────────────────────────"
    if bash "$HARNESS_DIR/score-one.sh" "$CHAL"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
done < "$SUBSET_FILE"

FINISHED=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo ""
echo "=== RUN SUMMARY ==="
echo "Started:  $STARTED"
echo "Finished: $FINISHED"
echo "Total:    $TOTAL"
# Count PASSes from the CSV (authoritative)
if [ -f "$RESULTS_CSV" ]; then
    CSV_PASS=$(awk -F, 'NR>1 && $4=="PASS" {c++} END {print c+0}' "$RESULTS_CSV")
    CSV_FAIL=$(awk -F, 'NR>1 && $4!="PASS" {c++} END {print c+0}' "$RESULTS_CSV")
    echo "PASS:     $CSV_PASS / $TOTAL"
    echo "FAIL:     $CSV_FAIL"
fi
echo ""
echo "Results CSV: $RESULTS_CSV"
echo "Runs dir:    $REPO_DIR/runs/"
