# HELP Command Test Coverage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 8 behavioral tests covering every code path of the `HELP` command dispatcher, bringing `make check` from 99 to 107 passing tests.

**Architecture:** The existing `make check` harness automatically discovers every `tests/*.cmd` file and diffs its stdout+stderr output against `tests/expected/<base>.out`. No Makefile changes needed. Tests are written first (`.cmd` only), run to confirm failure, then expected output is captured to make them pass — standard TDD for this harness.

**Tech Stack:** sdata interpreter (`./bin/sdata`), `make check` diff harness, bash.

---

### Task 1: Create HELP test scripts and capture expected output

**Files:**
- Create: `tests/help_index.cmd`
- Create: `tests/help_all.cmd`
- Create: `tests/help_use.cmd`
- Create: `tests/help_abs.cmd`
- Create: `tests/help_distributions.cmd`
- Create: `tests/help_unknown.cmd`
- Create: `tests/help_lowercase.cmd`
- Create: `tests/help_alias.cmd`
- Create: `tests/expected/help_index.out`
- Create: `tests/expected/help_all.out`
- Create: `tests/expected/help_use.out`
- Create: `tests/expected/help_abs.out`
- Create: `tests/expected/help_distributions.out`
- Create: `tests/expected/help_unknown.out`
- Create: `tests/expected/help_lowercase.out`
- Create: `tests/expected/help_alias.out`

Work from: `/home/jries/Develop/sdata`

- [ ] **Step 1: Create all 8 test scripts**

Each file contains exactly one line — the HELP invocation. No `QUIT` or other statements needed; the interpreter reads to EOF.

```bash
printf 'HELP\n'              > tests/help_index.cmd
printf 'HELP /ALL\n'         > tests/help_all.cmd
printf 'HELP USE\n'          > tests/help_use.cmd
printf 'HELP ABS\n'          > tests/help_abs.cmd
printf 'HELP DISTRIBUTIONS\n'> tests/help_distributions.cmd
printf 'HELP BOGUS\n'        > tests/help_unknown.cmd
printf 'HELP use\n'          > tests/help_lowercase.cmd
printf 'HELP DIST\n'         > tests/help_alias.cmd
```

- [ ] **Step 2: Verify the 8 scripts exist**

```bash
ls tests/help_*.cmd
```

Expected: 8 files listed.

- [ ] **Step 3: Run make check to confirm 8 new failures**

```bash
make check 2>&1 | grep -E "help_.*FAILED|tests FAILED"
```

Expected output (order may vary):

```
Testing tests/help_abs.cmd... FAILED (no expected output file)
Testing tests/help_alias.cmd... FAILED (no expected output file)
Testing tests/help_all.cmd... FAILED (no expected output file)
Testing tests/help_distributions.cmd... FAILED (no expected output file)
Testing tests/help_index.cmd... FAILED (no expected output file)
Testing tests/help_lowercase.cmd... FAILED (no expected output file)
Testing tests/help_unknown.cmd... FAILED (no expected output file)
Testing tests/help_use.cmd... FAILED (no expected output file)
8/107 tests FAILED:
```

If any of the 8 show a different failure reason (e.g., non-zero exit code or output mismatch against a stale `.out`), investigate before continuing. The only acceptable failure is `(no expected output file)`.

- [ ] **Step 4: Capture expected output for all 8 tests**

Run each script through the binary and save stdout+stderr (the harness captures both) to the expected directory:

```bash
./bin/sdata tests/help_index.cmd        > tests/expected/help_index.out 2>&1
./bin/sdata tests/help_all.cmd          > tests/expected/help_all.out 2>&1
./bin/sdata tests/help_use.cmd          > tests/expected/help_use.out 2>&1
./bin/sdata tests/help_abs.cmd          > tests/expected/help_abs.out 2>&1
./bin/sdata tests/help_distributions.cmd > tests/expected/help_distributions.out 2>&1
./bin/sdata tests/help_unknown.cmd      > tests/expected/help_unknown.out 2>&1
./bin/sdata tests/help_lowercase.cmd    > tests/expected/help_lowercase.out 2>&1
./bin/sdata tests/help_alias.cmd        > tests/expected/help_alias.out 2>&1
```

- [ ] **Step 5: Sanity-check three of the output files**

```bash
# Index: must start with "SData version"
head -1 tests/expected/help_index.out

# Unknown topic: must contain the error message
cat tests/expected/help_unknown.out

# Alias == Distributions: DIST and DISTRIBUTIONS must produce identical output
diff tests/expected/help_alias.out tests/expected/help_distributions.out && echo "IDENTICAL"

# Lowercase == Uppercase: 'use' and 'USE' must produce identical output
diff tests/expected/help_lowercase.out tests/expected/help_use.out && echo "IDENTICAL"
```

Expected:

```
SData version 0.6.6
Help topic not found: BOGUS
Type HELP for a list of commands and functions.
IDENTICAL
IDENTICAL
```

If either `diff` prints a delta instead of `IDENTICAL`, the case-normalisation or alias dispatch is broken — stop and investigate `sdata-help.adb` before proceeding.

- [ ] **Step 6: Run make check to confirm all 107 tests pass**

```bash
make check 2>&1 | tail -3
```

Expected:

```
All 107 tests passed.
```

If any of the 8 new tests fail with an output mismatch, compare the diff printed by `make check` against what you expect. A mismatch here usually means the capture in Step 4 picked up extra output (e.g., a spurious blank line). Re-run the capture command for just that test and re-run `make check`.

- [ ] **Step 7: Commit**

```bash
git add tests/help_*.cmd tests/expected/help_*.out
git commit -m "$(cat <<'EOF'
tests: add 8 HELP dispatcher coverage tests (107 total)

Covers all four Print_Help code paths: index (bare HELP), full reference
(/ALL), specific topic (USE, ABS, DISTRIBUTIONS), unknown topic (BOGUS),
plus case-insensitive lookup (use) and alias dispatch (DIST).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```
