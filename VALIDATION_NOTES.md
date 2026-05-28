# Coverage Spike Validation

Branch: `cc/coverage-spike`. Spec: `docs/superpowers/specs/2026-05-27-bash-coverage-spike-design.md`. Plan: `docs/superpowers/plans/2026-05-27-bash-coverage-spike.md`.

## Result: PASS

The mechanism works end-to-end across all three test layers (shunit unit, shunit functional, hatchet integration). A single `make coverage` (or manual three-step run) produces a SimpleCov HTML report at `coverage/index.html` with realistic per-file coverage numbers.

## Pipeline run

Trace inventory after one full pipeline:

| Source | Count |
|--------|-------|
| Docker `trace-*.log` (unit + functional) | 229 |
| Hatchet `hatchet-*.log` | 43 |
| **Total** | **272** |

The Ruby parser (`etc/generate-coverage-report`) merges all 272 trace files into a single SimpleCov resultset.

## Coverage results

After the lexer refinement (see `docs/superpowers/specs/2026-05-28-coverage-lexer-design.md`):

```
file                                total   hit  zero   nil    pct
----------------------------------------------------------------------
bin/compile                           580   290    97   193  74.9%
lib/binaries.sh                       320   136     1   183  99.3%
lib/builddata.sh                      174    33     6   135  84.6%
lib/cache.sh                          281   146    13   122  91.8%
lib/dependencies.sh                   432   254    11   167  95.8%
lib/environment.sh                    106    40    11    55  78.4%
lib/failure.sh                        976   311    95   570  76.6%
lib/features.sh                       186    42     7   137  85.7%
lib/json.sh                            51    12     7    32  63.2%
lib/kvstore.sh                         73    29     0    44 100.0%
lib/monitor.sh                         60    24     0    36 100.0%
lib/npm.sh                              5     1     0     4 100.0%
lib/output.sh                          77    22     4    51  84.6%
lib/plugin.sh                          53    26     0    27 100.0%
lib/uuid.sh                            47    11     3    33  78.6%
lib/yaml.sh                             9     4     0     5 100.0%
lib/yarn-2.sh                          91    43     1    47  97.7%
profile/WEB_CONCURRENCY.sh             88    31     7    50  81.6%
----------------------------------------------------------------------
TOTAL                                3609  1455   263  1891  84.7%
Files measured: 18
```

`hit` = lines that ran. `zero` = executable lines that did not run. `nil` = non-executable (blank, comment, structural token like `}`/`done`/`fi`/`else`, function declaration, case selector, or multi-line construct body).

Coverage jumped from 59.8% → 84.7% between the spike and this report. The trace data is identical — what changed is line classification. Bashcov-inspired rules now correctly identify lines that bash xtrace cannot trace (closing braces, control-flow keywords on their own line, heredoc bodies, etc.) and remove them from the denominator.

The `hit` count dropped (1578 → 1455). This is the philosophical flip on function declarations: the spike synthesized hits on `name() {` lines whenever the body ran. The refined report classifies declarations as non-executable (nil) — they register a name, they don't execute. SimpleCov treats nil lines as not counting for or against coverage, so the percentage rises despite the lower hit count.

What the cleaner numbers reveal:
- Files at or near 100% (`kvstore.sh`, `monitor.sh`, `plugin.sh`, `yaml.sh`, `npm.sh`) — narrow, well-exercised utility libraries.
- `bin/compile` at 74.9% — the entry point still has untested branches (mostly error/edge paths).
- `lib/failure.sh` at 76.6% — error-path code; the 95 untested executable lines are the genuine gap.
- `lib/json.sh` at 63.2% — narrowest test coverage of the libraries; real testing opportunity.

### Trace-wins overlay

The parser logs a warning when the lexer classifies a line non-executable but a trace records it ran. From this run:

- `lib/dependencies.sh` × 11 lines (around array literals on lines 22–23, 305, 317, 356, 377–380, 395, 411, 426)
- `lib/monitor.sh` × 3 lines (around the `local command=( "$@" )` array on line 50)
- `profile/WEB_CONCURRENCY.sh` × 2 lines

All trace into bashcov's "multi-line array" regex over-walking around `name=(...)` constructs. The trace-wins overlay catches them — they appear as covered in the report. Worth knowing about, not worth fixing in this iteration.

## Checkpoint history

### Task 7: Hatchet viability checkpoint — GREEN

After two false starts (collector lookup pattern broken; `BUILDPACK_COVERAGE` not propagating to bin/compile via `$ENV_DIR`), a single hatchet run of `spec/ci/node_26_spec.rb` produced 16 distinct files of trace data, ~3,800 lines per app, with `BASH_XTRACEFD` propagating cleanly to sourced files. Confirmed the buildpack-side instrumentation + post-deploy extraction pattern is viable.

### Task 10: Hatchet-only report checkpoint — GREEN (after one fix)

First parser run reported "100% coverage" because untouched lines defaulted to `nil`. Fixed: scan each watched source file, classify blanks/comments as `nil` and everything else as `0`, then promote to hit-count where the trace recorded one. Same hatchet-only data then reported 22.12% — realistic.

## Files measured vs. files that exist

The watched globs match 25 source files (`bin/*` × 6, `lib/*.sh` × 17, `profile/*` × 2). Of those:

- **18 measured** — listed above.
- **6 explicitly excluded** — `lib/coverage.sh` (the shim itself) plus `bin/detect`, `bin/release`, `bin/report`, `bin/test`, `bin/test-compile`. These are invoked outside `bin/compile`'s reach (slug-finalize, dyno-startup, or CI-only), so the shim never instruments them. Excluding them avoids reporting "0%" for files that the spike was never going to cover.
- **1 unmeasured but watched** — `profile/nodejs.sh`. Runs at dyno startup, never sourced from `bin/compile`. Its absence is a genuine gap and likely indicates a real unit-test opportunity.

## Known limitations (as documented in spec)

1. **Subshells in sourced scripts** — `BASH_XTRACEFD` does propagate (verified — multi-`+` traces from `lib/output.sh` and deeper subshells appear in trace files). The `+COV:` regex accepts 1+ leading `+` chars to handle this.
2. **Third-party scripts** — `npm`/`yarn`/`corepack` aren't instrumented; their lines are filtered by the watched globs.
3. **Concurrent test runs** — `make -j4` writes per-PID files (no collisions). The append-mode in the hatchet collector means re-deploys of the same `Hatchet::Runner` accumulate (intended).
4. **No branch coverage** — `set -x` doesn't distinguish taken/not-taken branches. Line coverage only.
5. **`set -x` perf overhead** — measured ~1.5–3× slowdown for instrumented runs. Acceptable for opt-in coverage builds.
6. **macOS host bash 3.2** — the shim requires bash 4.1+ (`BASH_XTRACEFD`). All Heroku stacks (heroku-22/24/26) ship bash 5+. Local smoke tests need `/usr/local/bin/bash`.

## What changed from the spec

Several deltas surfaced during execution. None blocked the spike, but worth noting before scaling this to other buildpacks:

- **Hatchet timing.** The spec's plan called for an rspec `after(:each)` hook to fetch traces. That fires *after* `app.deploy` returns — by which point Hatchet's `ensure` block has already torn the app down. Replaced with a `Hatchet::App#deploy` `prepend` that wraps the user's deploy block: collection runs after the user's block returns but inside the deploy lifecycle, before teardown.
- **`BUILDPACK_COVERAGE` propagation.** The spec assumed env-var propagation; in reality, Heroku's slug compiler delivers user config vars to `bin/compile` via `$ENV_DIR` (a directory of files), not the process environment. Shim now reads from `$ENV_DIR/BUILDPACK_COVERAGE` as a fallback.
- **Coverage semantics.** `Array.new(line_count, nil)` from the spec made every file report 100%. Replaced with a source-scanning initializer that defaults executable lines to `0` and blanks/comments to `nil`.
- **Self-contained shim.** The spec had the shim sourced after `BP_DIR` was computed by the caller. Refactored into a `coverage::enable` function callable from line 1 of any host script. The `BP_DIR` computation in `bin/compile`'s coverage prelude is intentionally duplicated from later setup so coverage activation never depends on the rest of the script's setup.
- **Function name in trace.** Added `${FUNCNAME[0]:-}` to the `PS4` so trace lines record the calling function. The parser uses this to attribute hits to function declarations (in addition to function bodies), making the report more readable for files that are mostly function definitions.
- **`make coverage` orchestration.** The target needed `.PHONY` (otherwise the existing `coverage/` dir short-circuits the recipe) and `CI=true` set when invoking `make hatchet` (which still calls `etc/ci-setup.sh` and that script hard-fails outside CI).
- **Append vs truncate for hatchet trace files.** Switched from `File.write` (truncating) to `File.open(..., "a")` so tests that re-deploy the same `Hatchet::Runner` (cache-reuse scenarios) accumulate traces rather than clobbering.

## Suggested next steps

If we want to keep this:

1. **Decide what gets upstreamed.** The makefile fixes (`.PHONY: coverage`, dropping `etc/ci-setup.sh` from `make hatchet`) might be worth landing independently. The shim and parser are spike artifacts that need their own design discussion before merging.
2. **Replicate to other bash buildpacks** (Python, Go, .NET, Java, PHP). The patterns proven here are reusable: `lib/coverage.sh`, the `coverage::enable` API, the parser, and the make/spec wiring. Each buildpack needs its own per-language `bin/compile` integration point and any equivalent of `test/unit` (e.g., shunit-based unit suites).
3. **CI integration.** Out of scope for the spike, but the natural next phase: a GitHub Action that runs `make coverage`, uploads the report as an artifact, and (optionally later) computes diff-coverage gates on PRs.
4. **`profile/nodejs.sh` test gap.** Real coverage gap that the spike surfaced. Worth a separate ticket to add unit tests for that file's behavior at dyno startup.
