# TRANSPOSE Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `TRANSPOSE` immediate-execution command that reshapes the current table — each transposed input column becomes one output row; either each input row becomes one output array element (`/ARRAY`, default `_X_`) or named subsets of rows become named output columns (`/ID`). With an active `BY`, each block is transposed separately into one output table. Respects active `SELECT`, flushes a pending `SAVE`, then clears `SELECT` + `BY` + pending SAVE.

**Architecture:** Shared `Execute_TRANSPOSE (Options : Transpose_Options)` lives in sdata-core's `SData_Core.Commands`; it block-scans the SELECT-filtered logical view, builds a fresh output table via the data-step output path (`Initialize_Output_Table → Add_Output_Column → Add_Output_Row → Set_Output_Value_By_Col → Commit_Output_Table`), re-registers subscripted arrays (`Register_Subscripted_Columns`), flushes a pending SAVE (`Flush_Pending_Save`), then clears SELECT + BY. sdata owns the lexer keyword, AST node, parser (USE-style slash-options), immediate dispatch, and HELP.

**Tech Stack:** Ada 2012, GNAT/GPRbuild, Alire. Two crates: `~/Develop/sdata-core` (shared lib, path-pinned) and `~/Develop/sdata` (this interpreter). Sibling consumer `~/Develop/data-vandal` must stay green (no change required).

**Source of truth:** `doc/specs/2026-06-01-transpose-design.md` (intent) as reconciled by `.ssd/features/transpose/01-architect.md` (corrections C1–C3 + drift D1–D7) and `.ssd/features/transpose/02-systems-designer.md` (production readiness). Where the spec and the architect doc disagree, **the architect doc wins** (it is grounded in verified source; the spec predates AGGREGATE).

## Global Constraints

- **sdata-core stays additive** → patch bump only, `0.1.17 → 0.1.18`. No exported signature is removed or changed. (architect D6)
- **Do NOT bump the consumer `sdata_core` floor.** `sdata/alire.toml` and `data-vandal/alire.toml` keep `sdata_core = "^0.1.16"`; `^0.1.16` already admits `0.1.18`. The `../sdata-core` path pin hides floor drift from `make check` — verify floors by reading `alire.toml`, not by trusting the build. (memory: floor-drift gotcha)
- **Cross-crate gate is mandatory before any commit that touches `src/`/tests/build files:** `cd ~/Develop/sdata-core && alr build` → `cd ~/Develop/sdata && make check` → `cd ~/Develop/data-vandal && make check`. All three green. Never `--no-verify`.
- **Error messages are verbatim** from spec §4.1 (see each task). ERR/ERL populated via `Execute_Record_Error`.
- **Validation order** inside `Execute_TRANSPOSE`: `4 → 5 → 8 → 9 → 11 → 10`, with `6`/`7` detected during the pre-scan (still before any output is built), `12` checked in the interpreter *before* dispatch, and `13` raised from the guarded SAVE flush; parse-time errors `1,2,3` in `Parse_TRANSPOSE`. Report only the first failing spec. **No side effect on any error before commit.** (spec §4, §4.3)
- **TRANSPOSE becomes a reserved keyword** — lexer enum + keyword chain + `sdata-reserved_keywords.adb` kept in sync (in-file comment requires it). (architect C2)
- **User-facing trio updated together:** built-in HELP (`src/sdata-help.adb`), man page (`man/man1/sdata.1`), design doc (`doc/design.md` — markdown, NOT `.odt`). Regenerate `tests/expected/help_all.out` + `help_index.out`. (CLAUDE.md)
- **TDD, frequent commits, DRY, YAGNI.** Each task ends green and committed.

## Layering note (read before starting)

The shared `Execute_TRANSPOSE` (sdata-core) and the sdata front-end are mutually dependent at *link* time: the interpreter calls `SData_Core.Commands.Execute_TRANSPOSE`, which must exist first. **Build order: Task 1 (sdata-core) first**, then sdata Tasks 2–6, then tests (7–8), then docs (9), then release (10). **End-to-end `.cmd` tests only go green after Tasks 1–6 are all wired.** Until then, develop Task 1 against `alr build` (compiles, no runtime exercise) and the parser unit tests (Task 8) which don't need the core.

## Build-and-swap call sequence (verified — Task 1 implements this verbatim)

From the landed `Execute_AGGREGATE` (`sdata_core-commands.adb:631-1028`), the exact ordered sequence TRANSPOSE mirrors:

```
-- validate (no side effect): #4 #5 #8 #9 #11 #10  → raise Script_Error on first
Rebuild_Filter_Map                       -- reflect active SELECT into Filter_Map
-- PRE-SCAN pass over logical view (also detects #6 #7 → still pre-mutation):
--   /ARRAY: K := max block size; /ID: union of ID values in first-encounter order
Tbl.Initialize_Output_Table
   Tbl.Add_Output_Column (By_Var_Name(i), Tbl.Get_Column_Type(By_Var_Name(i)))  -- each BY var
   Tbl.Add_Output_Column (Name_Col, Tbl.Col_String)                              -- _NAME_$ default
   -- value columns:
   --   /ARRAY: Add_Output_Column (Array_Name & "(" & trim(k) & ")", Set_Type) for k in 1..K
   --   /ID:    Add_Output_Column (id_colname(v), Set_Type) for v in union (first-encounter)
-- EMIT pass: for each block, for each transposed column C (schema/column order):
   Tbl.Add_Output_Row;  R := Tbl.Output_Row_Count;
   Set_Output_Value_By_Col (R, by_pos,   Get_Value(first_phys_of_block, By_Var_Name(i)))
   Set_Output_Value_By_Col (R, name_pos, (Val_String => literal name of C))
   -- /ARRAY: Set_Output_Value_By_Col (R, arr_pos(j), Get_Value(jth_phys_of_block, C))  j in 1..block_size
   -- /ID:    Set_Output_Value_By_Col (R, id_pos(v),  Get_Value(phys_with_id=v, C))      only present IDs
Tbl.Commit_Output_Table
Tbl.Clear_Index_Map
Vars.Refresh_PDV_Names
Vars.Register_Subscripted_Columns        -- registers _X_(1..K) as a DIM array
if SData_Core.Config.Runtime.Save_File_Active then Flush_Pending_Save end  -- #13 on failure
Execute_SELECT (null)
Tbl.Clear_By_Vars
```

Block boundary during both passes: scan `L in 1 .. Tbl.Logical_Row_Count`, `P := Logical_To_Physical(L)`; new block when `Tbl.By_Var_Count /= 0 and then not Tbl.In_Same_Group(P, Prev_P)`. Sparse `/ID` and short `/ARRAY` cells need **no special code**: `Add_Output_Row` pre-fills every column `Val_Missing`; only set the cells that exist.

## File Structure

```
sdata-core/
  src/sdata_core-commands.ads     -- + Transpose_Options record, + Execute_TRANSPOSE
  src/sdata_core-commands.adb     -- + Execute_TRANSPOSE body (validate → prescan → build → swap → flush → clear)
sdata/
  src/lexer/sdata-lexer.ads       -- + Token_TRANSPOSE
  src/lexer/sdata-lexer.adb       -- + "TRANSPOSE" keyword arm
  src/sdata-reserved_keywords.adb -- + S.Insert ("TRANSPOSE")
  src/ast/sdata-ast.ads           -- + Stmt_TRANSPOSE + payload fields
  src/ast/sdata-ast.adb           -- + Free arm (Free Keep_Vars/Drop_Vars)
  src/parser/sdata-parser.adb     -- + Parse_TRANSPOSE + dispatch arm (parse errors #1,#2,#3)
  src/sdata-interpreter.adb       -- + Is_Immediate, + Execute_Transpose worker (#12 guard), + dispatch arm, three-tier comment
  src/sdata-help.adb              -- + Help_TRANSPOSE + K_TRANSPOSE + table row + index line
  man/man1/sdata.1                -- + TRANSPOSE block
  doc/design.md                   -- + TRANSPOSE section
  doc/adrs.md                     -- + ADR-047
  doc/architecture.md             -- + Execute_TRANSPOSE in shared-commands list
  tests/transpose_*.cmd (+expected/*.out)  -- ~31 integration tests
  tests/sdata_unit_test.adb       -- + ~6 Parse_TRANSPOSE construction cases
  tests/expected/help_all.out, help_index.out  -- regenerated
  CLAUDE.md                       -- + TRANSPOSE in immediate-command list
```

---

### Task 1: `Transpose_Options` + `Execute_TRANSPOSE` (sdata-core)

**Files:** `sdata_core-commands.ads`, `sdata_core-commands.adb`. **Builds with `alr build`; runtime-exercised by Task 7.**

- [ ] Add the public record + procedure to `sdata_core-commands.ads` (mirror the `Aggregate_Spec`/`Execute_AGGREGATE` placement):
  ```ada
  type Transpose_Options is record
     Keep_List  : Name_Vectors.Vector;   -- empty = not specified
     Drop_List  : Name_Vectors.Vector;
     Name_Col   : Unbounded_String;       -- "" → default _NAME_$
     Id_Col     : Unbounded_String;
     Array_Name : Unbounded_String;       -- "" → default _X_ when neither /ID nor /ARRAY
     Has_Id     : Boolean := False;
     Has_Array  : Boolean := False;
  end record;
  procedure Execute_TRANSPOSE (Options : Transpose_Options);
  ```
  Confirm the `Name_Vectors` instantiation: reuse `SData_Core.Table.Name_Vectors` if re-exported by `Commands`; else add a local `package Name_Vectors is new Ada.Containers.Vectors (Positive, Unbounded_String)` (mirror however `Commands` already holds string lists for KEEP/DROP/USE).
- [ ] Implement `Execute_TRANSPOSE` body. Local helpers:
  - `Resolve_Transposed_Set` → ordered `Name_Vectors.Vector` of column names in **input schema order**: start from KEEP set (expand array names to element columns via the array registry) or all non-BY columns; subtract DROP set, the `/ID` column, and BY columns (§3.2). Validates #4 (unknown KEEP/DROP var), #5 (unknown /ID), #8 (mixed type), #9 (empty set). #11 (/ARRAY `$`-suffix vs set type), #10 (output-name collisions) computed once the set + output names are known.
  - `Pre_Scan` → forward block scan computing **K** (max block size) for /ARRAY, or the **ID union** (first-encounter order, with per-block duplicate detection → #6 and legal-identifier validation → #7) for /ID. With no BY: single pass.
  - `Set_Type` := the uniform `Column_Type` of the transposed set (`Col_Numeric` or `Col_String`).
- [ ] Build per the verified sequence above. **Empty input (§3.7):** if `Logical_Row_Count = 0`, build BY + `Name_Col` only, no value columns, zero rows, no warning, then still run commit/clear side-effects.
- [ ] Error #13: wrap `Flush_Pending_Save` in `exception when E : others => raise SData_Core.Script_Error with "TRANSPOSE: SAVE flush failed: " & Ada.Exceptions.Exception_Message (E);` (mirror AGGREGATE).
- [ ] `alr build` clean. Commit: `feat(commands): add Execute_TRANSPOSE (build-and-swap) [sdata-core]`.

**Note (fold into ADR-047 if confirmed):** like AGGREGATE's E1, array-name resolution in `/KEEP` must happen at execute time against the live registry, not parse time (batch mode has an empty registry until USE). And like E2, if `BY` auto-sorts, "non-adjacent runs" never occur — document the real behavior in the `transpose_consecutive_runs` test.

### Task 2: Lexer keyword `Token_TRANSPOSE` (sdata)

**Files:** `src/lexer/sdata-lexer.ads:31`, `src/lexer/sdata-lexer.adb:283`.

- [ ] Add `Token_TRANSPOSE,` to `Token_Kind` adjacent to `Token_AGGREGATE`.
- [ ] Add `elsif Upper = "TRANSPOSE" then T.Kind := Token_TRANSPOSE;` to the keyword chain.
- [ ] `/`-option names need NO lexer change (parser matches flag strings; `/` is `Token_Slash`).
- [ ] `alr build`. Commit with Task 3 (AST) since the enum is referenced there.

### Task 3: AST node `Stmt_TRANSPOSE` (sdata)

**Files:** `src/ast/sdata-ast.ads`, `src/ast/sdata-ast.adb`.

- [ ] Add `Stmt_TRANSPOSE` to `Statement_Kind` (ast.ads:185; add comma after `Stmt_AGGREGATE`).
- [ ] Add the case arm (simple-fields shape — no vector/access trio):
  ```ada
  when Stmt_TRANSPOSE =>
     Keep_Vars    : Variable_List;
     Drop_Vars    : Variable_List;
     Name_Col     : String (1 .. Max_Name_Len); Name_Col_Len  : Natural := 0;
     Id_Col       : String (1 .. Max_Name_Len); Id_Col_Len    : Natural := 0;
     Array_Col    : String (1 .. Max_Name_Len); Array_Col_Len : Natural := 0;
     Has_Id       : Boolean := False;
     Has_Array    : Boolean := False;
  ```
- [ ] Free arm in `ast.adb` (mirror `Free (Stmt.Sort_Vars)`): `when Stmt_TRANSPOSE => Free (Stmt.Keep_Vars); Free (Stmt.Drop_Vars);`. No new `Unchecked_Deallocation`.
- [ ] `alr build`. Commit: `feat(lexer,ast): Token_TRANSPOSE + Stmt_TRANSPOSE node`.

### Task 4: Parser `Parse_TRANSPOSE` + parse-time errors (sdata)

**Files:** `src/parser/sdata-parser.adb`. Reserved keyword in `src/sdata-reserved_keywords.adb`.

- [ ] Dispatch arm in `Parse_Statement` (parser.adb:2430): `when Token_TRANSPOSE => Stmt := new Statement (Stmt_TRANSPOSE); Parse_TRANSPOSE (Ctx, Stmt);`.
- [ ] `Parse_TRANSPOSE`: USE-style slash-option loop (model on parser.adb:1282-1341). `/KEEP=`, `/DROP=` → `Parse_Variable_List`; `/NAME=`, `/ID=`, `/ARRAY=` → single-token read into fixed-String fields. Enforce **at-most-once per option**; set `Has_Id`/`Has_Array`. Parse errors (hard-stop `raise Script_Error with "TRANSPOSE: ..."`, AGGREGATE style):
  1. both `/ID` and `/ARRAY` → `TRANSPOSE: /ID and /ARRAY are mutually exclusive`
  2. `/KEEP=`/`/DROP=` empty list → `TRANSPOSE: /<KEEP|DROP>= requires at least one variable`
  3. `/NAME` not ending `$` → `TRANSPOSE: /NAME column '<name>' must end in $ (character column required)`
- [ ] Add `S.Insert ("TRANSPOSE");` to `sdata-reserved_keywords.adb` (alphabetical: between `TO` and `UNHOLD`).
- [ ] `alr build`. Commit: `feat(parser): Parse_TRANSPOSE + slash-options + reserved keyword`.

### Task 5: Interpreter dispatch + error #12 guard (sdata)

**Files:** `src/sdata-interpreter.adb`.

- [ ] Add `| Stmt_TRANSPOSE` to `Is_Immediate` (interpreter.adb:103). Add TRANSPOSE to the three-tier execution comment (lines 35-42).
- [ ] Add `Execute_Transpose` worker (clone `Execute_Aggregate`, interpreter.adb:788-837): #12 guard `if Pending_Deferred > 0 then raise SData_Core.Script_Error with "TRANSPOSE: pending program statements exist; issue RUN or NEW first";`. Convert the AST node → `SData_Core.Commands.Transpose_Options` (Variable_Lists → `Name_Vectors`, fixed Strings → `Unbounded_String`, defaults applied: empty `Name_Col` and (no /ID, no /ARRAY) → `Array_Name := _X_`). Call `Execute_TRANSPOSE`. Print completion summary ("TRANSPOSE complete. N records and V variables processed.").
- [ ] Dispatch arm (interpreter.adb:944): `when Stmt_TRANSPOSE => Execute_Transpose (Stmt);`.
- [ ] `alr build`. Commit: `feat(interpreter): TRANSPOSE immediate dispatch + pending-buffer guard`.

### Task 6: HELP topic + snapshot regen (sdata)

**Files:** `src/sdata-help.adb`; regenerate `tests/expected/help_all.out`, `help_index.out`.

- [ ] `Help_TRANSPOSE` proc (style of `Help_AGGREGATE`, help.adb:232): syntax line, the five options, semantics summary, "Execution: Immediate". `K_TRANSPOSE : aliased constant String := "TRANSPOSE";` (help.adb:1200). Table row `(K_TRANSPOSE'Access, Help_TRANSPOSE'Access, C, N),` (help.adb:1414). Add TRANSPOSE to the Data-step index line (help.adb:21).
- [ ] Regenerate snapshots: `./bin/sdata tests/help_all.cmd > tests/expected/help_all.out`, same for `help_index`. Optional new `tests/help_transpose.cmd` + `tests/expected/help_transpose.out` (mirror `help_use`).
- [ ] Commit with Task 9 (docs) or standalone: `docs(help): HELP TRANSPOSE topic + snapshots`.

### Task 7: Integration tests (sdata) — the ~31 `.cmd` cases

**Files:** `tests/transpose_*.cmd` + `tests/expected/*.out` (+ fixture CSVs in `tests/data/` as needed). **These are the TDD spine for Task 1** — write them as you wire Tasks 1–6; they go green once the pipeline is connected.

- [ ] Feature-path tests (spec §7.1): `transpose_basic`, `transpose_id`, `transpose_by_id`, `transpose_by_id_union`, `transpose_by_array`, `transpose_keep`, `transpose_drop`, `transpose_keep_drop`, `transpose_keep_array_expansion`, `transpose_name`, `transpose_id_auto_exclude`, `transpose_select_active`, `transpose_save_flush`, `transpose_by_cleared`, `transpose_empty_input`, `transpose_consecutive_runs`, `transpose_default_array`, `transpose_character_set_id`, `transpose_character_set_array`.
- [ ] Error tests (one per error, assert verbatim message + exit code via `tests/<base>.exitcode` where non-zero): `transpose_id_and_array` (#1), `transpose_empty_keep` (#2), `transpose_name_no_dollar` (#3), `transpose_unknown_keep` (#4), `transpose_unknown_id` (#5), `transpose_dup_id` (#6), `transpose_bad_id_value` (#7), `transpose_mixed_types` (#8), `transpose_empty_set` (#9), `transpose_collision_by` (#10), `transpose_collision_name_array` (#10b), `transpose_array_suffix_mismatch` (#11), `transpose_buffer_nonempty` (#12).
- [ ] Author expected output by running the wired binary and inspecting for correctness (model on `aggregate_*` tests). Use the spec §5 worked examples to validate the value/`.`-padding layout.
- [ ] `make check` green (242 + new). Commit: `test(transpose): ~31 integration tests`.

### Task 8: Parser unit tests (sdata)

**Files:** `tests/sdata_unit_test.adb`.

- [ ] ~6 `Parse_TRANSPOSE` construction cases (spec §7.2): bare `TRANSPOSE` (defaults); `/KEEP`+`/DROP` combined; `/ID` only; `/ARRAY` only; `/NAME` custom; `/ID`+`/ARRAY` → parse error #1. Assert the resulting AST fields / raised message.
- [ ] `make check` green. Commit with Task 7 or standalone.

### Task 9: Documentation trio + ADR-047 + threat-model glance (sdata)

**Files:** `doc/design.md`, `man/man1/sdata.1`, `doc/adrs.md`, `doc/architecture.md`, `CLAUDE.md`, `doc/threat_model.md` (glance).

- [ ] `doc/design.md`: new TRANSPOSE section under Commands (syntax, semantics, BY/SELECT/SAVE interaction, option-by-option, error-catalog summary; cross-ref AGGREGATE).
- [ ] `man/man1/sdata.1`: `.TP`/`.B TRANSPOSE` block under immediate commands.
- [ ] `doc/adrs.md`: **ADR-047** capturing the five behavioral decisions (type-uniformity; union-of-IDs first-encounter + sparse-missing; max-K array bound + padding; /ID auto-exclusion; output-collision + `$`-suffix rules), and noting C1–C3 are AGGREGATE-derived mechanism corrections. Status Proposed → Accepted at merge.
- [ ] `doc/architecture.md`: add `Execute_TRANSPOSE` to the shared-commands list. `CLAUDE.md`: add TRANSPOSE to the immediate-command list.
- [ ] `doc/threat_model.md`: glance only — add a one-line per-command-surface note **only if** the doc already enumerates per-command surfaces; TRANSPOSE adds no new input surface (verify, do not invent a section).
- [ ] Doc-only commit (no `make check` required per CLAUDE.md exemption *unless* combined with the help-snapshot change, which touches `tests/expected/`): `docs: TRANSPOSE design.md + man + ADR-047 + architecture`.

### Task 10: Cross-crate gate, version bumps, tags (release)

- [ ] **Three-way gate:** `cd ~/Develop/sdata-core && alr build` → `cd ~/Develop/sdata && make check` (242+new) → `cd ~/Develop/data-vandal && make check` (unchanged, must stay green). All green.
- [ ] **Floor check:** read `sdata/alire.toml` + `data-vandal/alire.toml` — confirm `sdata_core = "^0.1.16"` unchanged (additive 0.1.18 satisfies it). Do NOT bump.
- [ ] **Versions:** `cd ~/Develop/sdata-core` → bump `alire.toml` `0.1.17 → 0.1.18`, tag `v0.1.18`. `cd ~/Develop/sdata` → `scripts/bump-version.sh <next> "TRANSPOSE command"`, tag.
- [ ] **PRs (sdata-core requires a PR; sdata too, per repo convention for this feature):** open sdata-core PR first (its CI validates against the pinned sdata tag); then sdata PR (CI red until sdata-core merges, since sdata `test.yml` clones `sdata-core@main`). data-vandal: no PR needed.
- [ ] Merge sdata-core PR first, then sdata PR. Sync both to main, delete branches.

---

## Self-Review

- [ ] Every spec §4 error (#1–#13) has exactly one integration test asserting the verbatim message; parse vs pre-exec vs scan vs post-exec phase matches §4.3.
- [ ] No side effect occurs before `Commit_Output_Table` on any error path (table unchanged on abort).
- [ ] `/ID` sparse + short-`/ARRAY` padding verified to render `.` (missing), not stale values — `transpose_by_id_union` + `transpose_by_array`.
- [ ] SELECT cleared (both `Clear_Index_Map` + `Execute_SELECT(null)`) and BY cleared post-TRANSPOSE — `transpose_select_active` + `transpose_by_cleared`.
- [ ] Pending SAVE flushed + cleared — `transpose_save_flush`.
- [ ] `_X_(1..K)` registered as a DIM array (subscripted access works post-TRANSPOSE) — assert in `transpose_by_array`.
- [ ] HELP/man/design.md updated together; `help_all.out` + `help_index.out` regenerated; reserved-word snapshots unshifted (TRANSPOSE now reserved).
- [ ] Three-way `make check` green; floors unchanged in both consumers; versions bumped + tagged; ADR-047 recorded.
