# CI Workflow Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Verify binaries" guard step to the existing GitHub Actions workflow so a missing `csv_unit_test` binary fails with a named CI step rather than inside the test harness.

**Architecture:** Single-file edit to `.github/workflows/test.yml`. Rename one existing step for clarity; insert one new `test -x` guard step between "Build" and "Run test suite". Alire version pin (`2.1.0`) matches the installed toolchain — no change needed.

**Tech Stack:** GitHub Actions YAML, `alire-project/setup-alire@v3`, Ubuntu runner.

---

### Task 1: Update `.github/workflows/test.yml`

**Files:**
- Modify: `.github/workflows/test.yml`

- [ ] **Step 1: Read the current workflow and confirm its exact content**

```bash
cat .github/workflows/test.yml
```

Expected output (verbatim — confirm before editing):

```yaml
name: CI

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Alire
        uses: alire-project/setup-alire@v3
        with:
          version: '2.1.0'

      - name: Install system dependencies
        run: sudo apt-get update && sudo apt-get install -y libsqlite3-dev

      - name: Fetch dependencies and build
        run: alr build

      - name: Run test suite
        run: alr exec -- make check
```

If the file differs (extra steps, different step names), adjust the edits below to match what is actually there — the logic is the same.

- [ ] **Step 2: Apply both changes**

Replace the "Fetch dependencies and build" step name with "Build" and insert the "Verify binaries" step immediately after it. The final file must be exactly:

```yaml
name: CI

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Alire
        uses: alire-project/setup-alire@v3
        with:
          version: '2.1.0'

      - name: Install system dependencies
        run: sudo apt-get update && sudo apt-get install -y libsqlite3-dev

      - name: Build
        run: alr build

      - name: Verify binaries
        run: test -x bin/sdata && test -x bin/csv_unit_test

      - name: Run test suite
        run: alr exec -- make check
```

- [ ] **Step 3: Validate the YAML is well-formed**

```bash
python3 -c "import yaml, sys; yaml.safe_load(open('.github/workflows/test.yml')); print('YAML OK')"
```

Expected: `YAML OK`

If you see a `yaml.scanner.ScannerError`, fix the indentation error before proceeding — YAML is indentation-sensitive and GitHub Actions silently ignores malformed workflows.

- [ ] **Step 4: Confirm the diff is exactly two hunks**

```bash
git diff .github/workflows/test.yml
```

Expected diff (two hunks, nothing else):

```diff
-      - name: Fetch dependencies and build
+      - name: Build
        run: alr build
+
+      - name: Verify binaries
+        run: test -x bin/sdata && test -x bin/csv_unit_test
+
       - name: Run test suite
```

If additional lines are changed, undo and redo Step 2.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/test.yml
git commit -m "CI: add Verify binaries step; rename Build step

Ensures csv_unit_test binary (added v0.6.6) is present before the
test harness runs, giving a named CI step on failure.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```
