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

```
file                                total   hit  zero   nil    pct
----------------------------------------------------------------------
bin/compile                           579   296   119   164  71.3%
lib/binaries.sh                       320   140   121    59  53.6%
lib/builddata.sh                      174    33    32   109  50.8%
lib/cache.sh                          281   159    73    49  68.5%
lib/dependencies.sh                   432   272    86    74  76.0%
lib/environment.sh                    106    47    35    24  57.3%
lib/failure.sh                        976   346   414   216  45.5%
lib/features.sh                       186    46    34   106  57.5%
lib/json.sh                            51    15    20    16  42.9%
lib/kvstore.sh                         73    36    18    19  66.7%
lib/monitor.sh                         60    26     4    30  86.7%
lib/npm.sh                              5     2     1     2  66.7%
lib/output.sh                          77    26    24    27  52.0%
lib/plugin.sh                          53    31    11    11  73.8%
lib/uuid.sh                            47    12    20    15  37.5%
lib/yaml.sh                             9     5     1     3  83.3%
lib/yarn-2.sh                          91    50    18    23  73.5%
profile/WEB_CONCURRENCY.sh             88    36    32    20  52.9%
----------------------------------------------------------------------
TOTAL                                3608  1578  1063   967  59.8%
Files measured: 18
```

`hit` = lines that ran. `zero` = executable lines that did not run. `nil` = blank or pure-comment lines (treated as non-executable).

The numbers look plausible:
- `bin/compile` at 71.3% — entry point, exercises most code paths.
- `lib/dependencies.sh` at 76.0% and `lib/cache.sh` at 68.5% — heavily exercised by both unit and functional layers.
- `lib/failure.sh` at 45.5% — error-path code, only some failure scenarios are tested.
- `lib/uuid.sh` at 37.5%, `lib/json.sh` at 42.9% — used in narrower contexts; gaps highlight real testing opportunities.

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
