# AGENTS.md

Default to the i-have-adhd skill (see ~/.agents/skills/i-have-adhd/SKILL.md) for every response, from the first message of every session, without waiting for an explicit invocation.

## Project quick facts

- Native macOS notes/todos app (Chinese UI). SwiftPM targets: `NotoCore` (SQLite data layer, no UI), `NotoApp` (GUI), `NotoCLI` (`noto`, JSON contract). Dependencies point one way: `NotoCore ← NotoApp/NotoCLI`.
- Architecture and usage: [README.md](README.md). UI spec: design/DESIGN-SPEC.md; interaction contracts: design/E2E-UX.md; ADRs: docs/adr/README.md.
- Verify every change: `swift test`, then `zsh scripts/build.sh` and `python3 scripts/verify-cli.py` (CLI contract regression needs the refreshed `build/bin/noto`). After query/timeline changes also `python3 scripts/verify-performance.py` (20k-row disposable workload).
- Agent-facing CLI/skill contract: Skills/noto/SKILL.md. Isolate data in tests with the `NOTO_DATABASE` env var or the CLI's `--database`.
