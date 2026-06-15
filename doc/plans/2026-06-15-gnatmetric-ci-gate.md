# gnatmetric Complexity Gate — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a blocking CI gate that fails when any subprogram in sdata's `src/` exceeds a cyclomatic-complexity ceiling, using `gnatmetric` from the Alire `libadalang_tools` crate.

**Architecture:** A provisioning script builds `gnatmetric` from a dedicated Alire sandbox (not a build dependency of sdata). A POSIX-shell gate script runs `gnatmetric` over `src/`, extracts each unit's cyclomatic complexity from XML output, and exits non-zero if the max exceeds a threshold derived from today's measured max. A `make complexity-check` target and a cached CI step wire it in. The unreachable `gnatcheck` enforcement is retained as manual/optional, with its false "Enforced in CI" comment corrected.

**Tech Stack:** Ada 2012 / GNAT / Alire; `libadalang_tools 26.0.0` (`gnatmetric`); POSIX `sh` + `awk`; GitHub Actions; GNU Make.

**Spec:** `doc/specs/2026-06-15-gnatmetric-ci-gate-design.md`

---

## File Structure

- **Create** `scripts/provision-gnatmetric.sh` — locate-or-build `gnatmetric`; print its absolute path. Idempotent.
- **Create** `scripts/check-complexity.sh` — the gate: run `gnatmetric`, parse max cyclomatic complexity, compare to `MAX_CYCLOMATIC`, exit non-zero on breach.
- **Modify** `Makefile` — add `complexity-check` target + `.PHONY` entry.
- **Modify** `.github/workflows/test.yml` — cache the built tool + add the gate step.
- **Modify** `.gitignore` — ignore `gnatmetric`'s `metrix.xml` output and the `tools/` sandbox.
- **Modify** `gnatcheck.rules` — correct the "Enforced in CI" header comment.
- **Modify** `doc/SOFTWARE_STANDARDS_REVIEW.md` — mark #7's static-analysis half addressed.

---

## Task 1: Provisioning script — build `gnatmetric`

**Files:**
- Create: `scripts/provision-gnatmetric.sh`
- Modify: `.gitignore`

- [ ] **Step 1: Write the provisioning script**

Create `scripts/provision-gnatmetric.sh`:

```sh
#!/bin/sh
# Locate or build gnatmetric (from the Alire libadalang_tools crate) and print
# its absolute path on stdout. Idempotent; called by `make complexity-check`
# and by CI. See doc/specs/2026-06-15-gnatmetric-ci-gate-design.md.
#
# Heavy on first run: building libadalang_tools pulls in libadalang from source.
# Subsequent runs reuse the built binary (and CI caches the tools/ directory).
set -eu

LAL_TOOLS_VERSION=26.0.0
TOOLS_DIR=${TOOLS_DIR:-tools}

# 1. Already on PATH (e.g. a distro/AdaCore install)?
if command -v gnatmetric >/dev/null 2>&1; then
  command -v gnatmetric
  exit 0
fi

# 2. Previously built under TOOLS_DIR?
existing=$(ls "$TOOLS_DIR"/libadalang_tools_*/bin/gnatmetric 2>/dev/null | head -n1 || true)
if [ -n "${existing:-}" ] && [ -x "$existing" ]; then
  printf '%s/gnatmetric\n' "$(cd "$(dirname "$existing")" && pwd)"
  exit 0
fi

# 3. Fetch and build it (heavy).
mkdir -p "$TOOLS_DIR"
( cd "$TOOLS_DIR" && alr -n get "libadalang_tools=$LAL_TOOLS_VERSION" )
crate_dir=$(ls -d "$TOOLS_DIR"/libadalang_tools_*/ 2>/dev/null | head -n1)
[ -n "${crate_dir:-}" ] || { echo "provision-gnatmetric: alr get produced no crate dir" >&2; exit 1; }
( cd "$crate_dir" && alr -n build )

bin="${crate_dir%/}/bin/gnatmetric"
if [ ! -x "$bin" ]; then
  bin=$(find "$crate_dir" -type f -name gnatmetric -perm -u+x 2>/dev/null | head -n1 || true)
fi
[ -x "${bin:-}" ] || { echo "provision-gnatmetric: build did not produce gnatmetric" >&2; exit 1; }
printf '%s/gnatmetric\n' "$(cd "$(dirname "$bin")" && pwd)"
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x scripts/provision-gnatmetric.sh`

- [ ] **Step 3: Ignore the sandbox + metrics output**

Append to `.gitignore` (create the lines if absent):

```
# gnatmetric complexity gate
/tools/
/metrix.xml
```

- [ ] **Step 4: Build gnatmetric (one-time, heavy)**

Run: `scripts/provision-gnatmetric.sh`
Expected: a long first build (libadalang from source), then a single line printing an absolute path ending in `/gnatmetric`. Capture it:

Run: `GM=$(scripts/provision-gnatmetric.sh); echo "$GM"; "$GM" --version`
Expected: prints the path, then gnatmetric's version banner (a `GNATMETRIC ... 26.x` line). If the build fails, stop and resolve the toolchain/network issue before continuing — every later task depends on this binary.

- [ ] **Step 5: Commit**

```bash
git add scripts/provision-gnatmetric.sh .gitignore
git commit -m "build: provisioning script for gnatmetric (libadalang_tools sandbox)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Discovery spike — invocation, metric label, measured max

This task is investigation, not TDD. It resolves three unknowns that Task 3's script depends on. Record each finding inline in this plan (edit the "→ RESULT" lines) so the next task is deterministic. No commit.

**Files:** none (read-only probing)

- [ ] **Step 1: Confirm the gnatmetric invocation that emits complexity XML**

Run (file-list mode — preferred, needs no project/`alr exec`):

```bash
GM=$(scripts/provision-gnatmetric.sh)
cd /home/jries/Develop/sdata
rm -f metrix.xml
"$GM" --xml --no-text-output --complexity-cyclomatic src/*.ads src/*.adb 2>/tmp/gm.err || true
ls -l metrix.xml && head -40 metrix.xml
```

Expected: `metrix.xml` is created and contains per-unit complexity metrics.
→ RESULT (fill in): does file-list mode produce `metrix.xml`? **YES / NO.**

If NO, try project mode (resolves `with`s via sdata-core on the path):

```bash
"$GM" --version   # confirm binary
alr exec -- "$GM" --xml --no-text-output --complexity-cyclomatic -P sdata.gpr 2>/tmp/gm.err || true
ls -l metrix.xml && head -40 metrix.xml
```

→ RESULT (fill in): chosen invocation = **file-list** / **`-P sdata.gpr` under `alr exec`**.
Record the exact flags that worked here: `____________________`

- [ ] **Step 2: Confirm the XML metric label for cyclomatic complexity**

Run: `grep -i cyclomatic metrix.xml | head`
Expected: lines like `<metric name="complexity_cyclomatic">7.00</metric>` (label may differ by version, e.g. `cyclomatic_complexity`).
→ RESULT (fill in): exact metric `name="..."` string = `____________________`

- [ ] **Step 3: Measure the current maximum cyclomatic complexity**

Run (substitute the confirmed label from Step 2 for `complexity_cyclomatic` if different):

```bash
awk '
  match($0, /name="[^"]+"/) { cur = substr($0, RSTART+6, RLENGTH-7) }
  /complexity_cyclomatic/ && match($0, /[0-9]+/) {
    v = substr($0, RSTART, RLENGTH) + 0
    if (v > max) { max = v; worst = cur }
  }
  END { printf "max=%d worst=%s\n", max, worst }
' metrix.xml
```

Expected: a single `max=<N> worst=<Unit>` line.
→ RESULT (fill in): measured max = **____**, worst unit = `____________________`

- [ ] **Step 4: Compute the threshold**

Rule: `MAX_CYCLOMATIC` = measured max rounded **up to the next multiple of 5**, with a minimum of **+3** headroom over the measured max (take the larger of the two). Example: measured 21 → next multiple of 5 is 25 (≥ 21+3=24) → **25**; measured 23 → next multiple of 5 is 25, but 23+3=26 > 25 → **26**.
→ RESULT (fill in): `MAX_CYCLOMATIC` = **____**

- [ ] **Step 5: Clean up the scratch output**

Run: `rm -f metrix.xml /tmp/gm.err`

---

## Task 3: Gate script `check-complexity.sh` (TDD)

**Files:**
- Create: `scripts/check-complexity.sh`

Use the Task 2 results: substitute the confirmed metric label and chosen invocation, and the computed `MAX_CYCLOMATIC`.

- [ ] **Step 1: Write the gate script**

Create `scripts/check-complexity.sh` (replace `complexity_cyclomatic`, the gnatmetric arg line, and the default `25` with the Task 2 results):

```sh
#!/bin/sh
# Cyclomatic-complexity gate for sdata src/.
# Fails (exit 1) if any unit's cyclomatic complexity exceeds MAX_CYCLOMATIC.
# Threshold derived from the measured maximum on 2026-06-15 (see plan Task 2);
# raise it deliberately only with justification.
# See doc/specs/2026-06-15-gnatmetric-ci-gate-design.md.
set -eu

MAX_CYCLOMATIC=${MAX_CYCLOMATIC:-25}            # <-- Task 2 Step 4 result
GNATMETRIC=${GNATMETRIC:-gnatmetric}

cd "$(dirname "$0")/.."                          # repo root

rm -f metrix.xml
# <-- Task 2 Step 1 confirmed invocation:
"$GNATMETRIC" --xml --no-text-output --complexity-cyclomatic src/*.ads src/*.adb \
  >/dev/null 2>&1 || true

if [ ! -f metrix.xml ]; then
  echo "check-complexity: gnatmetric produced no metrix.xml" >&2
  exit 2
fi

# <-- Task 2 Step 2 confirmed metric label in the /complexity_cyclomatic/ pattern:
result=$(awk '
  match($0, /name="[^"]+"/) { cur = substr($0, RSTART+6, RLENGTH-7) }
  /complexity_cyclomatic/ && match($0, /[0-9]+/) {
    v = substr($0, RSTART, RLENGTH) + 0
    if (v > max) { max = v; worst = cur }
  }
  END { printf "%d %s", max+0, worst }
' metrix.xml)
rm -f metrix.xml

max=${result%% *}
worst=${result#* }

if [ "$max" -gt "$MAX_CYCLOMATIC" ]; then
  echo "check-complexity: FAIL — '$worst' has cyclomatic complexity $max (max $MAX_CYCLOMATIC)" >&2
  exit 1
fi

echo "check-complexity: OK — max cyclomatic complexity $max (ceiling $MAX_CYCLOMATIC)"
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x scripts/check-complexity.sh`

- [ ] **Step 3: Verify it PASSES on current src/ (the "test")**

Run: `GNATMETRIC=$(scripts/provision-gnatmetric.sh) scripts/check-complexity.sh`
Expected: `check-complexity: OK — max cyclomatic complexity <N> (ceiling <MAX_CYCLOMATIC>)` and exit 0.
Confirm exit 0: `echo $?` → `0`.

- [ ] **Step 4: Verify the gate BITES (negative test)**

Run: `GNATMETRIC=$(scripts/provision-gnatmetric.sh) MAX_CYCLOMATIC=1 scripts/check-complexity.sh; echo "exit=$?"`
Expected: a `FAIL — '<Unit>' has cyclomatic complexity <N> (max 1)` line on stderr and `exit=1`.

- [ ] **Step 5: Commit**

```bash
git add scripts/check-complexity.sh
git commit -m "feat: cyclomatic-complexity gate script (gnatmetric)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: `make complexity-check` target

**Files:**
- Modify: `Makefile` (the `.PHONY` line at ~`Makefile:73`, and a new target near the `gnatcheck` target at ~`Makefile:174`)

- [ ] **Step 1: Add the target to `.PHONY`**

In `Makefile`, add `complexity-check` to the `.PHONY` list (the line beginning `.PHONY: all build clean run check fuzz-corpus gnatcheck ...`):

```make
.PHONY: all build clean run check fuzz-corpus gnatcheck complexity-check install srpm pkg msi \
```

(Keep the rest of the existing `.PHONY` line unchanged — append `complexity-check` after `gnatcheck`.)

- [ ] **Step 2: Add the target body**

Add immediately after the existing `gnatcheck:` target (after `Makefile:175`):

```make
complexity-check:
	@GNATMETRIC=$$(scripts/provision-gnatmetric.sh) scripts/check-complexity.sh
```

(Use a TAB for the recipe indent, per Makefile syntax.)

- [ ] **Step 3: Run the new target**

Run: `make complexity-check`
Expected: `check-complexity: OK — max cyclomatic complexity <N> (ceiling <MAX_CYCLOMATIC>)`, exit 0.

- [ ] **Step 4: Confirm the existing suite still passes (Makefile touched → full local check required per CLAUDE.md)**

Run: `make check`
Expected: all 5 unit-test binaries pass and all 202 integration tests pass (the standard green output). `complexity-check` is NOT part of `make check` by design — confirm `make check` runtime is unchanged.

- [ ] **Step 5: Commit**

```bash
git add Makefile
git commit -m "build: add make complexity-check target

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: CI wiring in `test.yml`

**Files:**
- Modify: `.github/workflows/test.yml` (append two steps after the existing `Fuzz corpus regression` step)

- [ ] **Step 1: Add cache + gate steps**

At the end of the `steps:` list in `.github/workflows/test.yml` (after the `Fuzz corpus regression` step), append:

```yaml
      - name: Cache gnatmetric (libadalang_tools)
        uses: actions/cache@v4
        with:
          path: sdata/tools
          key: gnatmetric-${{ runner.os }}-libadalang_tools-26.0.0

      - name: Complexity gate (gnatmetric)
        working-directory: sdata
        run: make complexity-check
```

Note: `make complexity-check` invokes `scripts/provision-gnatmetric.sh`, which builds `gnatmetric` into `sdata/tools/` on a cache miss and reuses it on a hit. The build uses the Alire toolchain already set up earlier in the job.

- [ ] **Step 2: Validate the workflow YAML locally**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/test.yml')); print('YAML OK')"`
Expected: `YAML OK` (no parse error). The full job can only be exercised by pushing; that is the accepted verification for the CI wiring.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/test.yml
git commit -m "ci: run gnatmetric complexity gate (cached) in test workflow

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Correct gnatcheck comment + update standards review

**Files:**
- Modify: `gnatcheck.rules` (header comment, ~lines 2-3)
- Modify: `doc/SOFTWARE_STANDARDS_REVIEW.md` (#7 entry)

- [ ] **Step 1: Fix the false "Enforced in CI" claim in `gnatcheck.rules`**

Replace the header comment lines:

```
--  Enforced in CI via "make gnatcheck" (alr exec -- make gnatcheck).
```

with:

```
--  Manual/optional: run with "make gnatcheck" where a gnatcheck binary is
--  available (gnatcheck is not in the Alire toolchain and is unpackaged on
--  several target distros). CI enforces static analysis via the gnatmetric
--  cyclomatic-complexity gate instead ("make complexity-check").
```

- [ ] **Step 2: Update the #7 entry in `doc/SOFTWARE_STANDARDS_REVIEW.md`**

Locate remediation **#7** (search the file for `#7` / "gnatcheck"). Mark its static-analysis half **addressed**, noting: gnatcheck is not Alire-provisionable / ASIS discontinued / unpackaged on Tumbleweed; CI now runs a `gnatmetric` cyclomatic-complexity gate (`make complexity-check`) built from `libadalang_tools`; the fuzz-driver half landed earlier (`44d0115`); `gnatcheck.rules` is retained as a manual tool. Reference `doc/specs/2026-06-15-gnatmetric-ci-gate-design.md`. Match the file's existing per-item formatting (read the surrounding entries first).

- [ ] **Step 3: Commit (doc + rules comment; no build impact)**

```bash
git add gnatcheck.rules doc/SOFTWARE_STANDARDS_REVIEW.md
git commit -m "docs: #7 static-analysis half addressed via gnatmetric complexity gate

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Final verification & integration

**Files:** none (verification + integration)

- [ ] **Step 1: Full local gate**

Run: `make check && make complexity-check`
Expected: integration suite green; complexity gate `OK`.

- [ ] **Step 2: Confirm no stray artifacts are tracked**

Run: `git status --porcelain`
Expected: clean (no `tools/`, no `metrix.xml` — both gitignored).

- [ ] **Step 3: Push and watch CI**

Run: `git push`
Then watch the run: `gh run watch $(gh run list --branch main --limit 1 --json databaseId --jq '.[0].databaseId')` (or `gh run list`).
Expected: the `test` job is green, including the new `Complexity gate (gnatmetric)` step. On the first run the cache misses and `gnatmetric` builds (slow); confirm the step still passes.

- [ ] **Step 4: Update SSD state**

This completes the `gnatmetric-ci-gate` feature. Record the landing in `.ssd/current.yml` `archived:` (slug `gnatmetric-ci-gate`, with the merge/commit SHA) and clear it from `active:` if present, per the `/ssd feature` close-out.

---

## Self-Review

**Spec coverage:**
- §2 decision (gnatmetric substitution) → Tasks 1-4.
- §4 provisioning (dedicated sandbox, not a build dep) → Task 1 (`tools/` sandbox; not added to `alire.toml`).
- §5 gate (wrapper, cyclomatic, threshold from measured max) → Tasks 2-3.
- §6 Makefile + CI, `make check` stays lean → Tasks 4-5.
- §7 gnatcheck retained, comment corrected → Task 6 Step 1.
- §8 docs (standards review; no `make check` desc change) → Task 6 Step 2.
- §9 testing (passes today; gate bites; cache) → Task 3 Steps 3-4, Task 5, Task 7.
- §10 risks (cache, format drift, threshold) → Task 2 discovery resolves format/threshold; Task 5 cache.

**Placeholder scan:** The "→ RESULT (fill in)" lines in Task 2 are *intended* empirical findings recorded during execution (the tool isn't installable in advance), each with an exact command and a deterministic decision rule — not vague placeholders. Task 3's script has marked substitution points tied directly to those results. No "TBD/handle edge cases/similar to Task N" remain.

**Type/name consistency:** `provision-gnatmetric.sh` prints a path consumed via `GNATMETRIC=$(...)` in Task 3 Step 3-4, Task 4 Step 2, and indirectly in CI; `check-complexity.sh` honours `GNATMETRIC` and `MAX_CYCLOMATIC`; `make complexity-check` and the `.PHONY` entry use the same target name throughout; `metrix.xml` and `tools/` are the same paths in the script, `.gitignore`, and the CI cache. Consistent.
