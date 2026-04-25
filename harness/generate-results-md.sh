#!/bin/bash
# Generate RESULTS.md from results.csv — run after a full benchmark run.
# Usage: generate-results-md.sh [results.csv] [RESULTS.md]
set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$HARNESS_DIR/.." && pwd)"
CSV="${1:-$REPO_DIR/results.csv}"
OUT="${2:-$REPO_DIR/RESULTS.md}"

if [ ! -f "$CSV" ]; then
    echo "ERR: $CSV not found" >&2
    exit 1
fi

python3 - "$CSV" "$OUT" <<'PYEOF'
import csv, sys, datetime, statistics, collections

csv_path, out_path = sys.argv[1], sys.argv[2]

rows = []
with open(csv_path, encoding="utf-8") as f:
    for row in csv.DictReader(f):
        rows.append(row)

if not rows:
    sys.exit("ERR: no data rows in csv")

total = len(rows)
passed = [r for r in rows if r["result"] == "PASS"]
failed = [r for r in rows if r["result"] != "PASS"]
pass_count = len(passed)
score_pct = 100.0 * pass_count / total

durations = [int(r["duration_sec"]) for r in rows if r["duration_sec"]]
median_dur = int(statistics.median(durations)) if durations else 0
total_dur = sum(durations)

# Per-level breakdown
by_level = collections.defaultdict(lambda: {"total": 0, "pass": 0})
for r in rows:
    lv = r["level"] or "?"
    by_level[lv]["total"] += 1
    if r["result"] == "PASS":
        by_level[lv]["pass"] += 1

# Per-category breakdown (tags are pipe-separated)
by_tag = collections.defaultdict(lambda: {"total": 0, "pass": 0})
for r in rows:
    for tag in (r["tags"] or "").split("|"):
        tag = tag.strip()
        if not tag:
            continue
        by_tag[tag]["total"] += 1
        if r["result"] == "PASS":
            by_tag[tag]["pass"] += 1

# Run metadata (take first row)
first = rows[0]
last = rows[-1]
started = first["started_at"]
finished = last["finished_at"]
model = first["model"]
bare = first["bare"]
bare_str = "bare (API key, --bare)" if bare == "1" else "non-bare (Claude Code OAuth)"

# Fail-reason categories
fail_counts = collections.Counter(r["result"] for r in failed)

lines = []
w = lines.append
w(f"# Results — spectre-xbow-bench 30-challenge subset")
w("")
w(f"**Score: {pass_count} / {total} PASS ({score_pct:.1f}%)**  ·  model `{model}`  ·  {bare_str}")
w("")
w(f"- Run started:  `{started}`")
w(f"- Run finished: `{finished}`")
w(f"- Total wall time (sum of per-challenge durations): {total_dur // 60}m {total_dur % 60}s")
w(f"- Median time per challenge: {median_dur}s")
w("")
w("## By difficulty level")
w("")
w("| Level | Solved | Total | % |")
w("|---|---|---|---|")
for lv in sorted(by_level):
    d = by_level[lv]
    pct = 100.0 * d["pass"] / d["total"] if d["total"] else 0
    w(f"| L{lv} | {d['pass']} | {d['total']} | {pct:.1f}% |")
w("")
w("## By vulnerability category")
w("")
w("| Category | Solved | Total | % |")
w("|---|---|---|---|")
for tag in sorted(by_tag):
    d = by_tag[tag]
    pct = 100.0 * d["pass"] / d["total"] if d["total"] else 0
    w(f"| {tag} | {d['pass']} | {d['total']} | {pct:.1f}% |")
w("")
if fail_counts:
    w("## Failure modes")
    w("")
    for k, v in fail_counts.items():
        w(f"- `{k}`: {v}")
    w("")
w("## Full results")
w("")
w("| Challenge | Level | Tags | Result | Duration | Flag match |")
w("|---|---|---|---|---|---|")
for r in rows:
    found = r["found_flag"] or ""
    expected = r["expected_flag"] or ""
    match = "✓" if found == expected else ("—" if not found or found == "NO_FLAG_FOUND" else "✗")
    dur = int(r["duration_sec"]) if r["duration_sec"] else 0
    w(f"| {r['challenge']} | L{r['level']} | {r['tags']} | **{r['result']}** | {dur}s | {match} |")
w("")
w("## Notes")
w("")
w(f"- Flag scheme: `FLAG{{sha256(XBEN-NNN-24)}}` — matches upstream `common.mk`.")
w(f"- No cherry-picks, no retries. `results.csv` is what the harness emitted.")
w(f"- Per-challenge transcripts at `runs/<challenge>/transcript.jsonl`.")
w(f"- Reproducibility posture: {bare_str}. See README for the canonical bare-mode variant.")

with open(out_path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")

print(f"wrote {out_path}: {pass_count}/{total} PASS ({score_pct:.1f}%)")
PYEOF
