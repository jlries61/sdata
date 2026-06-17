# Design Spec: gnatmetric Cyclomatic-Complexity Gate in CI

- **Slug:** `gnatmetric-ci-gate`
- **Date:** 2026-06-15
- **Author:** John L. Ries (with Claude Opus 4.8)
- **Status:** Approved (brainstorming) — ready for implementation plan
- **Addresses:** `doc/SOFTWARE_STANDARDS_REVIEW.md` remediation **#7** (static-analysis half).
  The fuzz-driver half of #7 already landed (`merge-rename-fuzz`, sdata main `44d0115`).

## 1. Problem

Remediation #7 calls for "gnatcheck/SAST in CI." Its fuzz-driver portion is done; the
**static-analysis-in-CI** portion was deferred and remains open. The deferral reason is
real and was confirmed during brainstorming:

- The Alire `gnat_native 15.2.1` toolchain ships only the FSF basics
  (`gnat`, `gnatbind`, `gnatls`, `gnatprep`, …) — **no `gnatcheck`**.
- There is **no `gnatcheck` (or `gnatsas`) crate** in the Alire index.
- FSF GNAT discontinued ASIS, so the historical `asis-programs` package is unreliable on
  modern distros; `gnatcheck` is **not packaged on openSUSE Tumbleweed** (the dev box) and
  is doubtful on current `ubuntu-latest`.
- Net effect: `make gnatcheck` cannot be run on the developer's machine **or** dependably
  provisioned in CI. The existing `gnatcheck.rules` comment claims "Enforced in CI via
  `make gnatcheck`" — this is **false**; CI never runs it.

We therefore need an automated static-analysis gate that is (a) provisionable identically
in CI and on a Tumbleweed dev box, and (b) genuinely enforceable.

## 2. Decision

Replace the unreachable `gnatcheck` enforcement with a **cyclomatic-complexity gate built
from `gnatmetric`**, provided by the Alire crate `libadalang_tools` (which installs through
the *same* Alire toolchain on both Tumbleweed and `ubuntu-latest`).

`libadalang_tools 26.0.0` ships exactly three executables — `gnatmetric`, `gnatpp`,
`gnatstub` — and **no `gnatcheck`**. Consequently this is a deliberate *substitution*, not a
port: the two existing custom rules (`Recursive_Subprograms`, `Too_Many_Parameters:8`)
cannot be reproduced by `gnatmetric` and are **not** carried over into the CI gate. They are
retained only as a manual/optional tool (see §7).

Rationale for choosing complexity over the alternatives considered:

- **gnatmetric complexity (chosen):** non-invasive — requires **zero reformatting** of the
  mature, hand-styled codebase; adds a real complexity ceiling.
- **gnatpp format gate (rejected):** opinionated; would fight the author's hand-formatting
  and likely demand a large reformat commit.
- **Real gnatcheck in CI (rejected):** fragile provisioning, version-pin babysitting, and
  still not locally runnable on Tumbleweed.
- **Advisory `continue-on-error` gnatcheck (rejected):** enforces nothing; rots silently.

## 3. Scope

- **In scope:** sdata **this crate's `src/` only**.
- **Out of scope:** `sdata-core` (separate crate, own CI), `tests/` drivers and fixtures,
  generated/`alire/` paths.
- **Not language-visible:** no `HELP`, `man/man1/sdata.1`, or `doc/design.md` changes
  (the "keep the user-facing surface in sync" rule in `CLAUDE.md` does not apply).

## 4. Tool Provisioning

`gnatmetric` is obtained from a **dedicated Alire sandbox**, *not* added as a dependency of
sdata (which would force every `alr build` to pull the heavy `libadalang` source build onto
the main build path).

- Fetch into a tool directory: `alr get libadalang_tools` (pins to a known crate version),
  then `alr build` once → produces `bin/gnatmetric`.
- **Local (Tumbleweed):** one-time `alr get`/`alr build`; thereafter `make complexity-check`
  reuses the built binary.
- **CI (`ubuntu-latest`):** a build step produces `gnatmetric`, cached via `actions/cache`
  keyed on the `libadalang_tools` crate version, so it rebuilds only when that version
  changes.

> **Caveat (accepted):** `libadalang_tools` pulls in `libadalang^26.0.0`, a large source
> build. Expect a meaningful one-time cost in CI (cached afterward) and a heavy first
> `alr build` locally. This is the accepted price of same-toolchain-everywhere provisioning.

The exact tool-directory location and whether the fetch is scripted or a committed sandbox
manifest is an implementation detail to be settled in the plan; the constraint is that it
must **not** appear in `sdata/alire.toml` as a build dependency.

## 5. The Gate

`gnatmetric` has **no native fail-on-threshold** behaviour, so a small, dependency-free
wrapper enforces the ceiling.

- **Script:** `scripts/check-complexity.sh` (POSIX `sh` + `awk`/`grep`; no Python/other
  runtime dependency — matches the existing Makefile shell-loop style).
- **Behaviour:** run `gnatmetric` over `src/`, extract each unit's **cyclomatic complexity**,
  compute the maximum, and exit non-zero if it exceeds `MAX_CYCLOMATIC`.
- **Output parsing:** grep a stable gnatmetric label (e.g. the per-subprogram
  `cyclomatic complexity` line); the crate is version-pinned so the format is stable. The
  plan must confirm the exact invocation/format (text vs `--xml`) against the built binary
  and pick the most stable one.
- **Threshold (`MAX_CYCLOMATIC`):** derived from **today's measured maximum** during
  implementation, rounded up with modest headroom, and recorded in the script with a comment
  citing the measured value and the date. This guarantees the gate **passes on current code**
  and only bites on *future* complexity growth.
- **Failure message:** name the offending unit(s) and their complexity vs the ceiling, so a
  CI failure is actionable without rerunning locally.

## 6. Makefile + CI Wiring

- **New target:** `make complexity-check` (mirrors the existing `gnatcheck` / `fuzz-corpus`
  targets; added to `.PHONY`). It assumes `gnatmetric` is available (built per §4) and runs
  `scripts/check-complexity.sh`.
- **CI:** a new step in `.github/workflows/test.yml`, after `make check` (and alongside the
  existing `make fuzz-corpus` step), runs the gnatmetric build/cache + `make complexity-check`.
  The step is **blocking** — acceptable here precisely because the gate *is* locally runnable
  (unlike gnatcheck) once `libadalang_tools` is built.
- **`make check` stays lean:** the gate is **not** folded into `make check`; it remains a
  separate CI step (and manual target) so the local unit/integration suite stays fast. This
  was an explicit decision.

## 7. Disposition of Existing gnatcheck Assets

- **`gnatcheck.rules`:** retained unchanged as documentation of intent and for anyone who has
  a `gnatcheck` binary. **Only** the misleading header comment is corrected — from
  "Enforced in CI via `make gnatcheck`" to wording that states it is a **manual/optional**
  tool and that CI enforces complexity via `make complexity-check`.
- **`make gnatcheck` target:** retained unchanged (manual/optional).
- **In-source `pragma Annotate (GNATcheck, …)` exemptions:** left in place; harmless and
  still valid for a manual gnatcheck run.

## 8. Documentation Updates

- **`doc/SOFTWARE_STANDARDS_REVIEW.md`:** mark #7's static-analysis half **addressed** via the
  gnatmetric complexity gate; note the gnatcheck-binary unavailability rationale and the
  substitution decision.
- **`CLAUDE.md`:** no change to the `make check` description (the gate is intentionally *not*
  part of `make check`). Optionally note the new `make complexity-check` target where CI
  targets are described, if a natural spot exists.
- **`gnatcheck.rules`:** comment correction per §7.

## 9. Testing / Verification

1. **Passes today:** `make complexity-check` exits 0 against current `src/`.
2. **Gate actually bites:** temporarily lower `MAX_CYCLOMATIC` below the measured max and
   confirm a non-zero exit naming the offending unit; restore the threshold.
3. **CI cache correctness:** confirm the `gnatmetric` build is cached and rebuilds only when
   the `libadalang_tools` crate version changes.
4. **Cross-crate gate unaffected:** `make check` (sdata, 202 integration tests) and
   `cd ~/Develop/data-vandal && make check` remain green — this change touches only sdata's
   CI/Makefile/scripts, not shared `sdata-core` code, so no sdata-core rebuild is required.

## 10. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| `libadalang_tools` build time / flakiness in CI | `actions/cache` keyed on crate version; pinned version |
| `gnatmetric` output-format drift | Version-pinned crate; wrapper greps a stable label; plan validates exact format against the built binary |
| Threshold too tight (false failures) or too loose (no signal) | Set from measured max + modest headroom; comment records the measurement |
| Heavy first local build on Tumbleweed | One-time; documented; not on the main build path |
| Future maintainers think `gnatcheck` is enforced | §7 comment correction removes the false claim |

## 11. Out of Scope / Future Work

- Adding `gnatpp` formatting enforcement (rejected for now — would fight hand-formatting).
- Extending the complexity gate to `sdata-core` (that crate owns its own CI gate decision).
- Additional gnatmetric metrics (nesting depth, unit size) as future ceilings.
- Reintroducing real `gnatcheck` if it later becomes Alire-provisionable.
