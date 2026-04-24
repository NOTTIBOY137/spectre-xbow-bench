.PHONY: bench one clean check-env help

BENCHMARKS_DIR ?= ../xbow-benchmarks
CHAL ?=

help:
	@echo "spectre-xbow-bench — reproducible XBOW subset"
	@echo ""
	@echo "Targets:"
	@echo "  make bench                     — run the locked 30-challenge subset"
	@echo "  make one CHAL=XBEN-020-24      — run a single challenge end-to-end"
	@echo "  make clean                     — remove runs/ and results.csv"
	@echo "  make check-env                 — sanity-check docker, openssl, claude, API key"
	@echo ""
	@echo "Env:"
	@echo "  ANTHROPIC_API_KEY=<sk-ant-...>  (required in bare mode)"
	@echo "  XBOW_BENCHMARKS_DIR=$(BENCHMARKS_DIR)"
	@echo "  XBOW_MODEL=opus  XBOW_MAX_BUDGET=5  XBOW_MAX_TURNS=60  XBOW_BARE=1"

check-env:
	@command -v docker >/dev/null || (echo "missing docker" && exit 1)
	@docker compose version >/dev/null 2>&1 || (echo "missing 'docker compose' plugin" && exit 1)
	@command -v openssl >/dev/null || (echo "missing openssl" && exit 1)
	@command -v claude >/dev/null || (echo "missing claude CLI — https://docs.claude.com/en/docs/claude-code" && exit 1)
	@command -v python3 >/dev/null || (echo "missing python3" && exit 1)
	@test -d "$(BENCHMARKS_DIR)/benchmarks" || (echo "missing xbow benchmarks at $(BENCHMARKS_DIR) — git clone https://github.com/xbow-engineering/validation-benchmarks.git $(BENCHMARKS_DIR)" && exit 1)
	@test -n "$${ANTHROPIC_API_KEY:-}" || test "$${XBOW_BARE:-1}" = "0" || (echo "ANTHROPIC_API_KEY unset (required for --bare mode). Either export the key or set XBOW_BARE=0 to use local Claude Code auth." && exit 1)
	@echo "ok."

bench: check-env
	@XBOW_BENCHMARKS_DIR=$$(cd "$(BENCHMARKS_DIR)" && pwd) bash harness/run-subset.sh

one: check-env
	@test -n "$(CHAL)" || (echo "usage: make one CHAL=XBEN-NNN-24" && exit 1)
	@XBOW_BENCHMARKS_DIR=$$(cd "$(BENCHMARKS_DIR)" && pwd) bash harness/score-one.sh $(CHAL)

clean:
	@rm -rf runs/ results.csv results.csv.prev
	@echo "cleaned runs/ and results.csv"
