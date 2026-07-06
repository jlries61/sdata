# SData — Statistical Data Interpreter

Ada 2012 CLI interpreter for tabular data processing, inspired by Systat BASIC's
data step model. Operates on a 2-D table of rows and columns (float, integer,
character). Single-process; batch and interactive modes.

## Repository Layout (Important)

Since v0.8.0, this is one of three sibling crates:

```
~/Develop/
├── sdata/          this repository — interactive interpreter
├── sdata-core/     shared Alire library — data layer, evaluator, command exec
└── data-vandal/    sister application — controlled data degradation
```

`sdata-core` is consumed via a path pin (`alire.toml`). Most data-layer,
evaluator, and shared command-execution code lives there now — **when touching
table / variables / evaluator / file I/O, modify `~/Develop/sdata-core/src/`,
not this crate**. This crate owns the sdata lexer, AST, parser, and the
sdata-only command implementations (LET, SET, PRINT, IF, FOR, WHILE, SORT,
AGGREGATE, TRANSPOSE, STATS, SUBMIT, BREAK, etc.). Build sdata-core too if you touch it: `cd ~/Develop/sdata-core && alr build`.

See ADR-039 through ADR-043 in `doc/adrs.md` for the split rationale.

### Cross-crate coordination (data-vandal is a PRIVATE sibling)

`data-vandal` is **intentionally unpublished** (the prospective employer wants the
vandalization code kept private), so **sdata-core's** CI cannot check it out —
`consumer-tests.yml` runs only the public sdata consumer. **A standards audit must
treat that as a deliberate privacy constraint, not a defect.**

What *is* automated (read the actual workflow files before claiming otherwise — an
earlier audit wrongly asserted "data-vandal is in no CI at all"):

- **sdata** `test.yml` and **data-vandal** `test.yml` each clone `sdata-core@main` on
  their own push/PR and run `make check`. A change *in either consumer* is therefore
  validated against current sdata-core automatically.
- **sdata-core** `consumer-tests.yml` validates an sdata-core change against sdata
  (pinned to a sdata release tag); `build.yml` smoke-builds the library + in-crate
  drivers. data-vandal is not run here (private).

The genuine gap is **one-directional**: an **sdata-core** change is auto-validated
against sdata (via the pin) but **not** against data-vandal until data-vandal next
pushes. So the local two-consumer gate is mandatory — it catches an sdata-core change
breaking data-vandal *promptly*, rather than waiting for data-vandal's next CI run:

- **Test any `sdata-core` change against BOTH consumers locally before pushing:**
  `cd ~/Develop/sdata-core && alr build`, then `cd ~/Develop/sdata && make check`,
  then `cd ~/Develop/data-vandal && make check`. All three must be green.
- **Keep the `sdata-core` version references current in BOTH repos.** When bumping
  `sdata-core`'s version, update the `sdata_core = "^X.Y.Z"` constraint in *both*
  `sdata/alire.toml` and `data-vandal/alire.toml`, and bump `sdata-core`'s
  `consumer-tests.yml` `ref:` (currently `v0.9.3`, behind sdata `0.9.7`) to a current
  sdata tag so its stability gate validates a current consumer.

## Build & Test

```bash
alr build            # preferred — uses Alire-managed GNAT toolchain
make build           # alternative if toolchain is on PATH
make check           # build + run all tests (unit + integration)
```

`make check` runs five unit-test binaries plus the integration suite (counts as
of v0.12.0; `make check` output is the source of truth):
1. `bin/csv_unit_test` — `SData_Core.CSV` functions (71)
2. `bin/sdata_unit_test` — `SData_Core.Table` / `Variables` / transient-table / merge / PDV (355)
3. `bin/evaluator_unit_test` — expression evaluator (170)
4. `bin/file_io_unit_test` — CSV/ODF/OOXML read-write (100)
5. `bin/interpreter_unit_test` — control flow / SELECT / REPEAT (97)
6. 299 `.cmd` integration tests in `tests/` (~793 unit checks total)

All 299 integration tests must pass before committing. Never use `--no-verify`.

**Documentation-only commits** — changes confined to `doc/`, `man/`, and `*.md`
(README, CONTRIBUTING, CLAUDE.md) and similar non-build prose — do **not** require a
local `make check` (or the cross-crate gate above); the suite is known-passing from
the last code change, and CI reruns on push as a backstop. This exemption does **not**
apply if the commit also touches `src/`, `tests/` (incl. `tests/expected/`), `*.gpr`,
`Makefile`, `alire.toml`, or packaging files — those still require the full local check
(and the cross-crate check if the change is in sdata-core).

If a sdata-core change is involved, run `cd ~/Develop/sdata-core && alr build`
first, then `cd ~/Develop/sdata && make check` to catch regressions in both layers.

## Key Architecture

**Three-tier execution model** (documented at top of `src/sdata-interpreter.adb`):

| Tier | Examples | Behaviour |
|---|---|---|
| Declarative | USE, BY, SELECT, REPEAT, SAVE, FPATH, RSEED | Execute immediately; configure interpreter state |
| Immediate | RUN, SORT, AGGREGATE, TRANSPOSE, STATS, NEW, NAMES, SYSTEM, HELP | Execute immediately; not purely declarative |
| Deferred | LET, SET, PRINT, IF, FOR, WHILE, WRITE, DELETE | Queued in statement list; execute once per record via `Run_One_Step` |

**PDV (Program Data Vector):** flat vector mirroring the current table schema.
`Load_PDV_From_Table` fills it; `Flush_PDV_To_Output` writes back. Column access
uses a pre-resolved cursor cache (`Column_Cursor_Cache`) — O(1), no per-row hash
lookups.

**SELECT filter:** expression stored persistently; rebuilt as a logical→physical
index map (`Filter_Map`) at the start of each `Run_One_Step`. All navigation
functions (RECNO, BOF, EOF, BOG, EOG, LAG, NEXT) operate in logical space.

**BY groups:** `SData_Core.Table` is the sole source of truth for BY variable
names. Use `By_Var_Count` / `By_Var_Name(I)` accessors; do not add a local copy
in the interpreter.

**Shared command execution:** `SData_Core.Commands.Execute_*` procedures
implement USE, SAVE, FPATH, OUTPUT, SELECT, KEEP, DROP, ARRAY, DIM, RUN, and
their related helpers (`Execute_OUTPUT_Table`, `Execute_Rebuild_Filter`). sdata's
interpreter delegates to these rather than duplicating the logic. data-vandal
calls the same procedures. When changing one of these commands' semantics, edit
sdata-core and confirm both `make check` (sdata, 299 integration tests) and
`cd ~/Develop/data-vandal && make check` (data-vandal, 144 integration tests) still pass.

## Source Layout

This crate (sdata-only code):

```
src/
  sdata-interpreter.adb       -- command dispatch, data step loop
  sdata-interpreter-execute_declarative.adb  -- declarative-command subunits
  sdata-interpreter-execute_assignment.adb   -- LET/SET handlers
  sdata-interpreter-execute_io.adb           -- PRINT/WRITE/SUBMIT handlers
  sdata-interpreter-execute_metadata.adb     -- NAMES/DROP/KEEP/ARRAY/DIM
  sdata-interpreter-execute_control_flow.adb -- IF/FOR/WHILE
  sdata-interpreter-process_one_record.adb   -- per-record deferred dispatch
  sdata-lexer.adb / sdata-lexer.ads          -- token recogniser
  sdata-parser.adb / sdata-parser.ads        -- AST builder
  sdata-ast.adb / sdata-ast.ads              -- statement AST node types
  sdata-help.adb              -- HELP topic dispatcher
  sdata-version.ads           -- Version_*/Copyright_* constants (per ADR-043)
  sdata-system.adb            -- sdata-only SYSTEM wrapper
tests/
  csv_unit_test.adb           -- SData_Core.CSV unit tests
  sdata_unit_test.adb         -- SData_Core.Variables / PDV unit tests
  *.cmd                       -- integration test scripts (201)
doc/
  SOFTWARE_STANDARDS_REVIEW.md  -- living standards audit (annotated)
  adrs.md                     -- 43 ADRs (ADR-001 through ADR-043; some gaps)
  architecture.md             -- package map, execution model, repo layout
  specs/                      -- design specs for completed features
  plans/                      -- implementation plans (step-by-step task lists)
```

Shared code (in `~/Develop/sdata-core/src/`):

```
sdata_core-commands.{ads,adb}     -- shared Execute_* procedures (USE, SAVE, etc.)
sdata_core-table.{ads,adb}        -- column-store table + SQLite spill
sdata_core-variables.{ads,adb}    -- PDV, temp/permanent symbols, hold semantics,
                                  --   Register_Subscripted_Columns (per ADR-041)
sdata_core-values.{ads,adb}       -- Value variant type + IEEE 754 infinity
sdata_core-evaluator.{ads,adb}    -- expression evaluator + Parse_Expression
sdata_core-evaluator-*.{ads,adb}  -- aggregate/distrib/misc/nav/numeric/string fns
sdata_core-file_io.{ads,adb}      -- CSV/ODF/OOXML read-write
sdata_core-csv.{ads,adb}          -- CSV tokeniser
sdata_core-statistics.{ads,adb}   -- aggregate / statistical helpers
sdata_core-config.{ads,adb}       -- static config + Config.Runtime mutable state
sdata_core-io.{ads,adb}           -- stdin/stdout/pager I/O
sdata_core-signals.{ads,adb}      -- SIGINT/SIGTERM cleanup
sdata_core-system.{ads,adb}       -- shell execution + privilege detection
```

## Keeping the user-facing surface in sync (HELP, man page, design doc)

When you change language-visible **syntax** — add or modify a command, function,
`OPTIONS` key, CLI flag, or statement form — update **all three** user-facing
references in the *same* change. They drift otherwise, and the built-in **HELP** has
historically been the one most often missed:

1. **Built-in HELP** — `src/sdata-help.adb` (the `HELP <topic>` and `HELP /ALL`
   output). This is the primary gap to watch. Updating it changes the `HELP /ALL`
   snapshot, so regenerate `tests/expected/help_all.out` — and any `options_display`
   / `*_options` expected output that lists the affected key.
2. **Man page** — `man/man1/sdata.1`.
3. **Design doc** — `doc/design.md` (the authoritative language spec).

A syntax change that updates only the parser/interpreter, or only one of the three
references, is incomplete.

## Reference Documents

**Design document** — `doc/design.md`

Markdown (converted from the former `design.odt` via pandoc); read directly. The
command and function references are HTML tables (faithful to the original
formatting and rendered by GitHub). Contains the authoritative language spec, data
model, command reference, built-in functions, and BY-group semantics. Consult it
before implementing or modifying any language-visible behaviour.

**Architecture Decision Records** — `doc/adrs.md`

Markdown; read directly. Documents 43 ADRs (ADR-001 through ADR-043, with a few
unused numbers) with rationale and status. ADRs 039–043 cover the sdata-core /
data-vandal split. Check for a relevant ADR before proposing a design change.

**Man page** — `man/man1/sdata.1`

Groff source; read directly. LANGUAGE OVERVIEW (line 138) and FUNCTIONS (line 379)
cover statements, expressions, and built-in functions concisely. Often faster to
scan than the full `design.md`.

**Threat model** — `doc/threat_model.md`

Markdown; read directly. Consult before adding any new external input surface
(file format, CLI flag, language statement), any new filesystem access, or any
change to the SYSTEM/SHELL/SUBMIT execution path. Documents the trust model,
attack surface table, nine STRIDE threats with mitigation status, and known gaps.

## Docs Convention

All committed documentation lives under `doc/` (singular). Subdirectory
conventions:

- `doc/specs/` — design specs (brainstorming output, feature designs)
- `doc/plans/` — implementation plans (step-by-step task lists)
- `doc/adrs.md` — Architecture Decision Records
- `doc/` (top-level) — man page, standards review, feasibility plan, and
  other reference documents

Use `doc/` for any new committed artifacts including ADRs and runbooks
generated by SSD skills.

Commit design specs and implementation plans to the repository as part of the
project record. They belong in git alongside the code they describe.

## Versioning

```bash
scripts/bump-version.sh <new-version> "<changelog summary>"
```

Updates 9 files: `src/sdata-version.ads`, `alire.toml`, `Makefile`, `sdata.spec`,
`slackware/sdata.{SlackBuild,info}`, `man/man1/sdata.1`, `README.md`,
`debian/changelog`. (sdata-core has its own independent version in
`~/Develop/sdata-core/alire.toml`; do not bump them together — see ADR-043.)
Commit the result, then create an annotated tag:

```bash
git tag -a v<new-version> -m "Version <new-version>"
```

**Bundled sdata-core version (packaging).** The version of the sdata-core
tarball bundled into the RPM/Debian/Slackware packages is **never hardcoded** —
it is derived from whatever sdata-core artifact is present in each build
context, so it cannot drift and needs no manual bump when sdata-core's version
changes:

- `Makefile` derives `SDATA_CORE_VERSION` from `../sdata-core/alire.toml`, and
  the `srpm` target injects that value into the spec copy in `rpmbuild/SPECS/`
  (so `sdata.spec`'s committed `%global sdata_core_version` is only a fallback).
- `debian/rules` and `slackware/sdata.SlackBuild` run standalone inside an
  unpacked source tree where `../sdata-core` is unavailable, so they derive the
  version by globbing the bundled `sdata-core-*` directory shipped alongside
  them.

Each derivation assumes exactly one `sdata-core-*` artifact per build context;
the `make clean` at the start of every packaging target guards against a stale
one lingering. Do not reintroduce a hardcoded sdata-core version in these files.

## Phase Status

- Phases 1–4: **complete** (core, control flow, distributions/aggregates, spreadsheet I/O)
- Phase 5 (Polish): **complete** — disk spillover, interactive improvements, pager, HELP, LIST, ERR/ERL, error messages, performance, documentation
- Phase 6 (Testing): **ongoing** — 299 integration tests, ~733 unit checks across 5 modules
- v0.8.0 milestone (2026-05-21): VANDALIZE extracted into `data-vandal`; sdata-core shared library created (ADRs 039–043)
- STATS command (2026-07-01): SData's PROC MEANS analogue — per-variable summary statistics, one row per (BY group × variable), reusing the aggregate machinery (sdata v0.12.0, sdata-core v0.1.19; ADR-048)

Full plan: `doc/feasibility_assessment.md`

## SSD Convention

This project uses Shippable States Development. Working artifacts live in `.ssd/`
(gitignored). Primary SSD commands:

- `/ssd feature <name>` — architect → systems-designer → coder → review loop
- `/ssd milestone` — post-sprint audit (codebase-skeptic → refactor → verify)

See `.ssd/README.md` for the artifact tree, `.ssd/init-log.md` for prerequisite
check results.
