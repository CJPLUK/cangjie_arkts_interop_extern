## Checks

Run from `arkts_runtime/`.

- **`./hostcheck.sh`** (seconds, no device): type-checks the Cangjie package with the DevEco SDK's `cjc`, as shipped and for the test app, then the step tests' package; syntax-checks `native/*.cpp` against the SDK's N-API headers, in debug and release (`-DNDEBUG`), with warnings as errors; runs `native/budget_test.cpp`. Use it as the typecheck after every change. The host's own `cjc` cannot build this package: it has no `Extern` support.
- **`./devicetest.sh`** (minutes, needs a connected device): builds the test app, installs it and runs the full suite, including the step tests and the differential suite. Run it once at the end of a piece of work. Use `-s class <Class>` to run one class, for example `-s class Lifetime`. If no device is connected, say so rather than skipping silently.

## Agent skills

### Issue tracker

Issues and specs live in GitHub Issues on CJPLUK/cangjie_arkts_interop_extern, managed with the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five default labels (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
