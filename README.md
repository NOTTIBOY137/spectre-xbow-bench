# spectre-xbow-bench

Reproducible subset of the [XBOW validation-benchmarks](https://github.com/xbow-engineering/validation-benchmarks)
run through a single-agent Claude solver with per-challenge transcripts, tool-call logs,
timing, and CSV results.

> **Status:** work in progress. Results will be published here once the full subset run completes.
> **Honest floor:** we publish whatever the harness outputs — no retries, no cherry-picks.

## What this is

A minimal, public, **reproducible** benchmark run. Clone the repo, bring an Anthropic API
key, and `make bench`. You get the same numbers (modulo non-determinism in the agent
loop) that show up in `results.csv`.

## Why a 30-challenge subset (not 104)

- **Build reality.** On a stock Windows + Docker Desktop + Git-bash host, 21 of XBOW's
  104 challenges fail to `docker compose build` — mostly PhantomJS apt-install failures
  (the package was removed from Debian mirrors). Rather than cherry-pick around broken
  builds, we locked a subset of 30 that all build cleanly from `main`.
- **Stratified.** 15 L1 + 13 L2 + 2 L3, covering all 19 major vulnerability categories
  (XSS, IDOR, SQLi/blind, SSTI, SSRF, XXE, command injection, deserialization, JWT,
  crypto, privilege escalation, business logic, GraphQL, NoSQLi, LFI, path traversal,
  CVE, file upload, race condition).
- **See `harness/subset.txt`** for the exact list.

## Quick start

```bash
# 1. Clone XBOW benchmarks as sibling (or set XBOW_BENCHMARKS_DIR to your clone path)
git clone https://github.com/xbow-engineering/validation-benchmarks.git ../xbow-benchmarks

# 2. Pick an auth path:

#    (a) API key — canonical reproducible posture (--bare mode)
export ANTHROPIC_API_KEY=sk-ant-...
make bench

#    (b) Local Claude Code subscription — convenient, non-bare
export XBOW_BARE=0
make bench          # uses your logged-in `claude` OAuth session
```

On completion:
- `results.csv` — one row per challenge: PASS/FAIL, duration, found vs expected flag
- `runs/XBEN-NNN-24/transcript.jsonl` — full stream-json transcript of the solver
- `runs/XBEN-NNN-24/build.log`, `boot.log`, `solver.log` — phase-by-phase logs
- `runs/XBEN-NNN-24/result.json` — compact per-challenge summary

## Reproducibility contract

- **Flag scheme:** `FLAG{sha256(XBEN-NNN-24)}` — matches upstream `common.mk`. We do not
  hardcode flags. Each challenge builds with its canonical flag injected as a
  `--build-arg`.
- **Model:** `claude-opus-4-7` (override with `XBOW_MODEL=...`).
- **Solver isolation:**
  - With `XBOW_BARE=1` (default): `--bare` strips hooks, plugins, CLAUDE.md
    auto-discovery, keychain auth. Only `ANTHROPIC_API_KEY` honored. Strongest
    reproducibility.
  - With `XBOW_BARE=0`: uses Claude Code OAuth, but still applies
    `--setting-sources ""`, `--tools "Bash"`, custom `--system-prompt`, and
    `--permission-mode bypassPermissions` to minimize local-env bleed. The `bare`
    column in `results.csv` reflects which posture each row ran under.
- **Budget cap:** `$3` per challenge, `60` tool-use turns, `25 min` wall-clock.
  Override via `XBOW_MAX_BUDGET`, `XBOW_MAX_TURNS`, `XBOW_SOLVE_TIMEOUT`.
- **Validation:** the found flag must be a 68-char string `FLAG{<64 hex>}` exactly equal
  to the expected SHA-256 digest of the challenge ID. No partial credit.
- **CSV is overwritten between full runs.** A `results.csv.prev` backup is kept.

## Configuration

| Env var | Default | Purpose |
|---|---|---|
| `ANTHROPIC_API_KEY` | — (required) | API key for the solver |
| `XBOW_BENCHMARKS_DIR` | `../xbow-benchmarks` | Path to your clone of xbow-engineering/validation-benchmarks |
| `XBOW_MODEL` | `opus` | Model alias or full ID |
| `XBOW_MAX_TURNS` | `60` | Hard cap on tool-use turns |
| `XBOW_MAX_BUDGET` | `3` | Dollars/challenge |
| `XBOW_SOLVE_TIMEOUT` | `1500` | Seconds wall-clock per challenge |
| `XBOW_BARE` | `1` | `1` = bare + API key (canonical). `0` = Claude Code OAuth (dev) |

## Layout

```
spectre-xbow-bench/
├── harness/
│   ├── subset.txt       # locked 30-challenge list
│   ├── run-subset.sh    # driver (foreach → score-one.sh)
│   ├── score-one.sh     # build → run → solve → validate → teardown
│   ├── solver.sh        # wraps `claude -p` (stream-json, bash-only tools)
│   ├── validate.sh      # flag match
│   └── port.sh          # docker compose port discovery
├── runs/                # per-challenge artifacts (created on run)
├── results.csv          # authoritative results (created on run)
├── Makefile
├── LICENSE              # MIT
└── README.md
```

## Caveats (don't skip these)

1. **Non-determinism.** The agent loop is not seed-deterministic. Running twice may give
   different pass/fail distributions by a small margin. This is inherent to LLM-driven
   solvers. We publish the exact transcript of each run so readers can audit specific
   solves.
2. **Not the full 104.** We skip 74 other challenges, including some that XBOW's own
   pipeline solves. A higher score on 30 is not directly comparable to a score on 104.
3. **Single-agent.** This harness invokes one Claude process per challenge. It does not
   use the SPECTRE multi-agent wave orchestration — that is a different layer of
   production tooling and a fair subject for a follow-up benchmark.
4. **No leaderboard claim.** The upstream XBOW repo does not publish a public
   leaderboard. Numbers here stand on their own.

## License

MIT — see `LICENSE`.

Benchmark challenges themselves are Apache-2.0 licensed by the XBOW project; this repo
does not redistribute them.
