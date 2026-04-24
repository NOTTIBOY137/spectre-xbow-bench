#!/bin/bash
# Score a single XBEN challenge end-to-end: build → run → solve → validate → stop.
# Writes per-challenge artifacts to ../runs/<CHAL>/ and appends a row to ../results.csv.
# Usage: score-one.sh XBEN-NNN-24
set -uo pipefail

CHAL="${1:?usage: score-one.sh XBEN-NNN-24}"

HARNESS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$HARNESS_DIR/.." && pwd)"
BENCH_DIR="${XBOW_BENCHMARKS_DIR:-$(cd "$REPO_DIR/../xbow-benchmarks" && pwd)}"

CHAL_DIR="$BENCH_DIR/benchmarks/$CHAL"
RUN_DIR="$REPO_DIR/runs/$CHAL"
RESULTS_CSV="$REPO_DIR/results.csv"
mkdir -p "$RUN_DIR"

# Init CSV header once
if [ ! -f "$RESULTS_CSV" ]; then
    echo "challenge,level,tags,result,duration_sec,found_flag,expected_flag,started_at,finished_at,port,model,bare" > "$RESULTS_CSV"
fi

# Metadata lookups
META_FILE="$CHAL_DIR/benchmark.json"
LEVEL=$(python3 -c "import json,sys; print(json.load(sys.stdin).get('level',''))" < "$META_FILE" 2>/dev/null || echo "")
TAGS=$(python3 -c "import json,sys; print('|'.join(json.load(sys.stdin).get('tags',[])))" < "$META_FILE" 2>/dev/null || echo "")

# Canonical flag
FLAG_HEX=$(echo -n "$CHAL" | openssl sha256 -r | cut -d' ' -f1)
FLAG_FMT="FLAG{$FLAG_HEX}"
echo "$FLAG_FMT" > "$RUN_DIR/expected_flag.txt"

# Timing
STARTED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
T0=$(date +%s)

cleanup() {
    (cd "$CHAL_DIR" && docker compose down -v > "$RUN_DIR/teardown.log" 2>&1 || true)
}
trap cleanup EXIT

echo "[$STARTED] score-one $CHAL (L$LEVEL) $TAGS"

# 1. Build with canonical flag (rebuild is fast if cached)
echo "  build..." | tee -a "$RUN_DIR/phase.log"
if ! (cd "$CHAL_DIR" && docker compose build \
        --build-arg FLAG="$FLAG_FMT" --build-arg flag="$FLAG_FMT" \
        > "$RUN_DIR/build.log" 2>&1); then
    echo "  BUILD FAILED" | tee -a "$RUN_DIR/phase.log"
    T1=$(date +%s); FINISHED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    echo "$CHAL,$LEVEL,$TAGS,BUILD_FAIL,$((T1-T0)),,${FLAG_FMT},$STARTED,$FINISHED,,,${XBOW_BARE:-1}" >> "$RESULTS_CSV"
    exit 2
fi

# 2. Boot (docker compose up -d --wait honors healthchecks)
echo "  boot..." | tee -a "$RUN_DIR/phase.log"
if ! (cd "$CHAL_DIR" && docker compose up -d --wait > "$RUN_DIR/boot.log" 2>&1); then
    echo "  BOOT FAILED" | tee -a "$RUN_DIR/phase.log"
    T1=$(date +%s); FINISHED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    echo "$CHAL,$LEVEL,$TAGS,BOOT_FAIL,$((T1-T0)),,${FLAG_FMT},$STARTED,$FINISHED,,,${XBOW_BARE:-1}" >> "$RESULTS_CSV"
    exit 3
fi

# 3. Port discovery
PORT=$("$HARNESS_DIR/port.sh" "$CHAL" 2>"$RUN_DIR/port.err" || echo "")
if [ -z "$PORT" ]; then
    echo "  PORT DISCOVERY FAILED" | tee -a "$RUN_DIR/phase.log"
    T1=$(date +%s); FINISHED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    echo "$CHAL,$LEVEL,$TAGS,PORT_FAIL,$((T1-T0)),,${FLAG_FMT},$STARTED,$FINISHED,,,${XBOW_BARE:-1}" >> "$RESULTS_CSV"
    exit 4
fi
TARGET_URL="http://localhost:$PORT"
echo "  target: $TARGET_URL" | tee -a "$RUN_DIR/phase.log"

# Give the app a moment to stabilize (healthcheck may report ready before routes work)
sleep 3

# 4. Solve
echo "  solve..." | tee -a "$RUN_DIR/phase.log"
SOLVE_TIMEOUT="${XBOW_SOLVE_TIMEOUT:-1800}"
timeout "$SOLVE_TIMEOUT" "$HARNESS_DIR/solver.sh" "$CHAL" "$TARGET_URL" "$RUN_DIR" \
    > "$RUN_DIR/solver.log" 2>&1 || true

# 5. Validate
RESULT=$("$HARNESS_DIR/validate.sh" "$CHAL" "$RUN_DIR" 2>/dev/null || echo "FAIL")
FOUND=$(cat "$RUN_DIR/found_flag.txt" 2>/dev/null || echo "")

T1=$(date +%s)
DUR=$((T1 - T0))
FINISHED=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo "  $RESULT  duration=${DUR}s  found=$FOUND"
# CSV escape (commas in tags already replaced with |)
echo "$CHAL,$LEVEL,$TAGS,$RESULT,$DUR,$FOUND,$FLAG_FMT,$STARTED,$FINISHED,$PORT,${XBOW_MODEL:-opus},${XBOW_BARE:-1}" >> "$RESULTS_CSV"

# 6. Persist a compact result.json
cat > "$RUN_DIR/result.json" <<EOF
{
  "challenge": "$CHAL",
  "level": "$LEVEL",
  "tags": "$TAGS",
  "result": "$RESULT",
  "duration_sec": $DUR,
  "found_flag": "$FOUND",
  "expected_flag": "$FLAG_FMT",
  "started_at": "$STARTED",
  "finished_at": "$FINISHED",
  "port": $PORT,
  "model": "${XBOW_MODEL:-opus}",
  "bare": ${XBOW_BARE:-1}
}
EOF
