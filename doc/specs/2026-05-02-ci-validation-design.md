# CI Workflow Validation: Verify csv_unit_test Binary

## Goal

Validate and tighten the existing `.github/workflows/test.yml` so it correctly
handles the `csv_unit_test` binary added in v0.6.6. No structural changes to
the workflow; one new guard step and a cosmetic rename.

## Background

The `test.yml` workflow was created in v0.3.2. It runs:

1. `alr build` — builds via Alire/gprbuild; produces `bin/sdata` and
   `bin/csv_unit_test` (both listed in `sdata.gpr`'s `for Main use (...)`).
2. `alr exec -- make check` — runs `make check` inside the Alire environment
   where `gprbuild` and `GPR_PROJECT_PATH` are set. `make check` now runs
   `./bin/csv_unit_test` before the `.cmd` integration suite.

The workflow should work as-is, but if either binary is absent (e.g., a future
`sdata.gpr` change accidentally removes `csv_unit_test.adb` from `Main`), the
failure is buried in test-harness output rather than flagged at the build stage.

## Change

**File:** `.github/workflows/test.yml`

| # | Change | Rationale |
|---|---|---|
| 1 | Rename step "Fetch dependencies and build" → "Build" | Cosmetic clarity |
| 2 | Add "Verify binaries" step after "Build" | Explicit guard; named CI step |
| 3 | Verify `setup-alire@v3` and `version: '2.1.0'` are current | Ensure pin matches latest stable release |

### New "Verify binaries" step

```yaml
- name: Verify binaries
  run: test -x bin/sdata && test -x bin/csv_unit_test
```

Placed between "Build" and "Run test suite". Exits non-zero (and fails the job
with the step name shown) if either binary is missing or non-executable.

## What Is Not Changing

- Trigger: `push` and `pull_request` on `main`
- Runner: `ubuntu-latest`
- `libsqlite3-dev` install step
- `alr exec -- make check` step and name
- No Makefile changes
- No multi-platform matrix (deferred per CRITIQUE.md)

## Success Criteria

1. Workflow file lints cleanly (valid YAML, no schema errors).
2. `alr build` produces both `bin/sdata` and `bin/csv_unit_test`.
3. "Verify binaries" step passes.
4. "Run test suite" step passes (33 unit tests + 99 cmd tests).
5. No other CI behaviour changes.
