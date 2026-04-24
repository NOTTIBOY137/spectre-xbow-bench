#!/bin/bash
# Discover the published host port for a running XBEN challenge.
# Assumes exactly one service in the compose has a `ports:` entry (XBOW convention).
# Usage: port.sh XBEN-NNN-24
set -euo pipefail

CHAL="${1:?usage: port.sh XBEN-NNN-24}"
BENCH_DIR="${XBOW_BENCHMARKS_DIR:-$(cd "$(dirname "$0")/../../xbow-benchmarks" && pwd)}"
CHAL_DIR="$BENCH_DIR/benchmarks/$CHAL"

if [ ! -d "$CHAL_DIR" ]; then
    echo "ERR: challenge dir not found: $CHAL_DIR" >&2
    exit 1
fi

# Parse `docker compose ps --format json` and extract the first PublishedPort.
# Each line is one service as JSON. Use python3 for portable JSON parsing.
PORT=$(cd "$CHAL_DIR" && docker compose ps --format json 2>/dev/null | python3 -c "
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        svc = json.loads(line)
    except json.JSONDecodeError:
        # Some docker versions emit a single JSON array instead of NDJSON
        try:
            arr = json.loads(line)
            if isinstance(arr, list):
                for svc in arr:
                    for p in (svc.get('Publishers') or []):
                        pub = p.get('PublishedPort') or 0
                        if pub:
                            print(pub); sys.exit(0)
        except Exception:
            pass
        continue
    for p in (svc.get('Publishers') or []):
        pub = p.get('PublishedPort') or 0
        if pub:
            print(pub); sys.exit(0)
")

if [ -z "$PORT" ]; then
    echo "ERR: no published port found for $CHAL" >&2
    exit 2
fi

echo "$PORT"
