# Software Standards Audit: `SData` Ecosystem (`sdata` + `sdata-core`)

**Date:** 2026-09-26 | **Mode:** Adversarial single (ecosystem treated as one system — sdata + its
path-pinned sdata-core; complementary layers, not competing alternatives)
**Snapshot:** sdata `5785a9d` (v0.37.0) + sdata-core `a24bfcc` (v0.16.0)
**Auditor:** `/software-standards` v1.1.1, invoked via `/ssd audit`
**Standalone report:** `.ssd/audits/2026-09-26-sdata-ecosystem/standards-report.md`

**This document was regenerated from scratch, by explicit instruction, replacing everything below
this line.** Prior versions of this document (last living score: 640/800, stamped 2026-07-08; full
history in `doc/SOFTWARE_STANDARDS_REVIEW_bak.md` and git history) used an incremental-delta
methodology — carry the score forward, patch only what a given session happened to touch. That
methodology's own July 2026 audit found it had let two dimensions sit unexamined against genuinely
new code for a full month. This pass does not carry forward any prior narrative, score, or citation;
every finding below was independently re-derived against the current tree. **The resulting total
(581/800) is not comparable to 640/800 and should not be read as a regression** — see "Overall
Score" below for why.

**Verification this pass:** `alr build` clean in both crates (exit 0). `make check` — **all 721
integration tests + all unit-test binaries pass** (exit 0; confirmed on a second, uncontaminated run
after a first run's 4 spurious `exit 126` failures were traced to this session's own concurrent `alr
build` racing the test loop's binary, not a defect — each of the four re-ran clean standalone).
`scripts/check-complexity.sh` — max cyclomatic complexity 81 (`SData_Main`), ceiling 85. Shippable
state confirmed.

---

## 1. Architectural Integrity — **79/100**

The three-crate split (ADRs 039–043: sdata / sdata-core / data-vandal) is real and **acyclic** —
`alr show --tree` for sdata shows `sdata_core` as the only path-pinned dependency, and sdata-core's
own `alire.toml` depends on nothing that imports back (`zipada`, `xmlada`, `mathpaqs`,
`ada_sqlite3` only). ADR-040's no-lexer/AST/parser-in-core rule is honored: `grep -l "Token_Kind\|
Statement_Kind" sdata-core/src/*.ads` returns nothing. `CLAUDE.md` plus `doc/architecture.md` give a
genuinely 30-minute-readable map of the split and the three-tier execution model
(Declarative/Immediate/Deferred), and that tier boundary has a real enforcement point (the ADR-056
loop-placement warning set), not just prose.

Two things cost points:

- **The shared-command façade is real but its concentration is uneven.** `SData_Core.Commands`
  (`sdata_core-commands.adb`, 2050 lines) is the single largest file in either crate and contains
  both of the ecosystem's two largest individual procedures by a wide margin (`Execute_TRANSPOSE`,
  372 lines, `commands.adb:1289-1661`; `Execute_AGGREGATE`, 360 lines, `commands.adb:909-1269`).
  Nothing is wrong with sharing logic in one file — that is the architecture's stated purpose — but
  a "structural coherence" claim has to reckon with two of the busiest command handlers being this
  large *within* the layer designed to keep things thin.
- **`ada_sqlite3` is pinned at `0.1.1` — "the only published version" per sdata-core's own
  `alire.toml` comment — with a documented, deliberate leak (`Backing_Store.Finalize` does not free
  its sqlite handle) to dodge a double-finalization crash in that exact version. This is well
  cited and honestly labeled ("REVISIT" note in `sdata_core-table.adb`), which is the right way to
  carry unavoidable debt — but it means one of five direct third-party dependencies is a
  single-maintainer, sub-1.0, known-buggy package the whole storage-spill path routes through.

## 2. Code Quality & Craftsmanship — **65/100**

Naming is consistently good (`Execute_Rebuild_Filter`, `Register_Subscripted_Columns`,
`Column_Cursor_Cache` — no `data`/`temp`/`x` scattered through the shared layer), and there is
**zero** `TODO`/`FIXME`/`HACK`/`XXX` anywhere in either crate's `src/` (`grep -rnE
"TODO|FIXME|HACK|XXX" src/ sdata-core/src/` → 0 hits) — debt here is tracked in ADRs and
`doc/threat_model.md`'s Known Gaps table, not left as inline promises to nobody.

Function size is the real debit, and it is concentrated exactly where the language does the most
work:

- **`Execute_Declarative`** (`sdata-interpreter-execute_declarative.adb:6-1046`, 1041 lines) is a
  single flat `case Stmt.Kind is` with only 10 branches (`grep -c "when Stmt_" → 10`). The `Stmt_USE`
  branch alone spans **lines 23–632 — 610 lines in one `case` arm**, handling CSV/ODF/OOXML dispatch,
  `/MISSING=`, `/TYPES=`, and reserved-column warnings inline rather than through named helpers.
- **`Execute_Tables`** (`sdata-interpreter-execute_tables.adb`, the entire 1565-line file is one
  `separate` procedure body) is architecturally better than it looks at a glance — it decomposes
  into ~20 named nested subprograms (`Render_Two_Way_Grid`, 181 lines at `:253-434`; `Render_List`,
  193 lines at `:1179-1372`; `Save_Request_Rows`, 134 lines at `:763-897`) rather than one flat
  block — but several of those nested subprograms are themselves in the 130–200 line range, each
  mixing layout arithmetic with I/O formatting.
- A file-wide scan of unambiguously-delimited subprograms (`procedure/function … is` through a
  matching `end Name;`) across both crates' largest files puts **`SData_Main`** at 550 lines
  (`sdata_main.adb:38-588`) and **`Parse_Expression`** at 495 lines
  (`sdata_core-evaluator.adb:777-1272`) as the next two outliers after the two above.

None of this is *complexity* by the project's own measured metric — `check-complexity.sh` reports
max McCabe complexity 81 against a self-set ceiling of 85, and that ceiling has not moved since it
was set from the same `SData_Main` measurement months ago. That is worth naming plainly: length and
McCabe complexity are different axes, and this codebase is long in places without (by that one
metric) being complex. But a 610-line `case` arm and a 372-line shared procedure are still a
readability and single-responsibility cost by the skill's own bar ("over 100 lines is architectural
failure") regardless of what the cyclomatic gate says about them.

Exception handling, by contrast, is genuinely disciplined: 18 true `exception … when others`
handlers exist across both crates' `.adb` files, and inspecting all 18 shows the dominant pattern is
resource-cleanup-then-`raise` (`Free_Buf`/`Close`/`Unchain`/state-restore, then `raise;` —
e.g. `sdata_core-file_io-odf.adb:544`, `sdata-interpreter.adb:643`), not silent swallowing. Exactly
one handler is a bare `null;` catch-all with no cleanup or re-raise: `sdata_core-io.adb:43`, in the
interactive `-- More --` pager prompt's `Get_Line` — defensible in isolation (a pager-prompt read
failure shouldn't crash the interpreter) but broad enough to also mask a `Storage_Error` or
`Program_Error` there, not just the I/O conditions it was written for.

## 3. Efficiency & Performance — **72/100**

The project has a genuine, cited history of finding and fixing real algorithmic debt (the 2026-07-08
audit's own remediation record: STATS/TABLES O(n²) hoisted to O(rows), `Render_List`'s combinatorial
odometer replaced, both landed on measured code, not asserted). The complexity gate
(`check-complexity.sh`, CI-enforced via `.github/workflows/test.yml`) is real infrastructure most
solo Ada projects don't have.

Two debits:

- **The gate's ceiling has essentially no headroom.** `MAX_CYCLOMATIC=85`, current max 81
  (`SData_Main`) — the ceiling was set as "next multiple of 5 above the measured max" at the time it
  was introduced and has not been revisited since; 4 points of slack on a codebase that has
  added STATS, TABLES, PCTL, and multiple new option surfaces since is thin margin for a gate whose
  whole point is to catch growth before it compounds.
- **`doc/performance_assessment.md` is stale by any reasonable measure**: dated 2026-04-24,
  stamped **version 0.6.1**, against a current tree at **0.37.0** — five months and roughly thirty
  minor releases later, spanning the entire three-crate split (v0.8.0) and every command added
  since. Every number in it (row-scaling throughput, startup overhead) describes a codebase that no
  longer exists in this form. It is the one performance artifact in the tree, and it is not current
  by a wide margin.

## 4. Maintainability & Evolvability — **83/100**

`make check` passes clean: **721/721 integration tests**, all unit-test binaries green, confirmed by
this audit's own uncontaminated run (not carried forward from a prior report). Test naming is
specific and behavior-scoped (`use_merge_err_by_missing.cmd`, `tables_twoway_partial_missing.cmd`),
not vague smoke tests. 84 ADRs in sdata's own series plus 27 in sdata-core's give a real,
contiguous decision record — `doc/adrs.md` and `sdata-core/docs/decisions/` are both current as of
this session (touched the same day as the v0.37.0 release).

The debit here is CI **existing without being enforced** (scored under Operational Readiness below,
but it bears on evolvability too): a contributor — including the sole maintainer — can push a
change that breaks `make check` straight to `main` in sdata with nothing stopping it, so the test
suite's completeness is a discipline the maintainer keeps, not a property the repository
structurally guarantees. `.ssd/current.yml` in both sdata and sdata-core show real, if occasionally
lagging, workstream tracking (per this project's own memory, sdata-core has previously gone ~6 weeks
untracked from exactly this gap — ADR-0009 — and this audit's own preceding session found and closed
one more instance of it, `verify-data-vandal-against-pr-153`, the same day).

## 5. Error Handling & Resilience — **84/100**

A single, consistently-used exception convention (`Script_Error`, defined once per crate in
`sdata.ads:8` / `sdata_core.ads:28`, referenced 168 times across both `.adb` trees) carries
essentially all user-facing error signaling. Combined with §2's finding above (cleanup-then-`raise`
dominant in the 18 genuine exception handlers), this is a codebase that treats errors as data to be
reported accurately, not conditions to be hidden. `doc/threat_model.md` §5.5/5.6 document specific,
named failure modes (D1–D5, E1–E2) with an explicit accepted/mitigated/partially-mitigated status
for each, rather than a vague "we handle errors" claim.

The one debit is the same `sdata_core-io.adb:43` catch-all noted in §2 — a single instance, but it
is the one place in the audited exception-handling surface where "recoverable vs. unrecoverable" is
not actually distinguished, just uniformly ignored.

## 6. Security Posture — **72/100**

`doc/threat_model.md` is a real STRIDE analysis (§5.1–5.6, 10 named threats T1–E2) with a Risk
Summary table carrying an explicit status per threat, not a generic security statement. SQL
injection (T1) is mitigated via `Sql_Id` applied at every name origin; ODF/OOXML zip-bomb and
malformed-archive risk (T2) has actual fuzz corpus regression (`ods_fuzz_driver`,
`xlsx_fuzz_driver`, wired into `make fuzz-corpus`); `SYSTEM`/`SHELL` arbitrary execution (E1) is
named "Accepted by design" rather than pretended away, with `--noshell`/`--nosubmit` as the actual
mitigation and `--shell-timeout` closing the DoS half (D2). No hardcoded secrets anywhere in either
crate's `src/` (checked directly; none found).

The debit is currency: **`doc/threat_model.md` was last touched 2026-09-03 and has zero mentions of
`USE /MISSING=` or `USE /TYPES=`** (`grep -ni "MISSING\|TYPES=" doc/threat_model.md` → no hits
outside an unrelated `File_Name` note) — both are new external-input surfaces added after that date
(ADR-083/ADR-084, merged 09-25 and 09-26), and `CLAUDE.md` itself instructs consulting/updating this
document "before adding any new external input surface." Both features shipped without that step.
Neither introduces an obviously exploitable hole on inspection (they're user-declared string tokens
compared against parsed field values, not passed to a shell or a query), but the *process* the
project states for itself did not run, and the document is consequently incomplete against its own
stated scope.

## 7. Operational Readiness — **58/100**

Real CI exists in both repos: sdata's `test.yml` runs the full suite plus the complexity gate;
sdata-core's `build.yml` smoke-builds plus in-crate tests, and `consumer-tests.yml` checks out sdata
at a pinned tag and re-runs its full suite against sdata-core's tree on every push/PR — genuine
cross-repo regression coverage most single-maintainer library splits don't bother building.

But CI's output is **not a merge gate anywhere in this ecosystem**, verified directly against the
GitHub API rather than assumed:

- `gh api repos/jlries61/sdata/rulesets` → `[]`. No branch protection, no ruleset, no required
  checks. Confirmed consistent with the project's own stated convention (direct push to `main`
  allowed), but it means "all tests pass" for sdata is enforced by nothing but the maintainer's own
  discipline.
- `gh api repos/jlries61/sdata-core/rulesets/16766300` → an active ruleset requiring a pull request
  (no direct push, no force-push, no branch deletion) — but with **`required_approving_review_count:
  0`** and **no `required_status_checks` rule present at all**. A PR can be opened and merged by its
  own author, with zero reviews and without `build.yml` or `consumer-tests.yml` having reported
  success. The classic branch-protection API (`.../branches/main/protection`) reports "Not
  Protected" here, which is the misleading half of the picture — the ruleset is real and does block
  direct pushes — but neither mechanism actually requires the CI that exists to pass before a merge
  lands.
- No coverage instrumentation anywhere (`grep -rn "gnatcov\|gcov" Makefile .github/workflows/` → no
  hits). Test *count* is tracked and deliberately not quoted in prose (ADR-079, to avoid exactly the
  kind of stale-number drift this audit is elsewhere flagging), but there is no line/branch coverage
  figure at all, staleness-prone or otherwise.

Structured logging, metrics, and tracing are absent, but this is a single-process batch/interactive
CLI interpreter, not a service — that class of software legitimately has no dashboards or SLOs to
speak of, so this sub-item is scored as **not applicable** rather than counted against the total; the
58/100 above reflects only the merge-gate and coverage gaps, which do apply.

## 8. Documentation — **68/100**

`doc/design.md` (2026-09-26), `doc/adrs.md` (2026-09-26), `README.md` (2026-09-26), and
`man/man1/sdata.1` (2026-09-26) are all current as of the same day as the v0.37.0 release —
genuinely well-maintained, not coincidentally untouched. `CLAUDE.md`'s own three-way sync rule
(HELP/man-page/design-doc updated together for any syntax change) gives this currency a real
enforcement mechanism, not just good habits.

Two documents drag the average down, both identified directly rather than inferred:

- **`doc/performance_assessment.md`** — five months and ~30 releases stale (§3 above); this is the
  single worst documentation-currency finding in the audit, a genuine "museum" artifact by the
  skill's own test ("is the documentation current, or a museum of lies?").
- **`doc/threat_model.md`** — 23 days stale relative to two shipped external-input-surface features
  it should name and doesn't (§6 above); `doc/architecture.md` is comparatively minor at 26 days
  behind the split's most recent work, with no evidence of drift beyond age.

This document's own prior incarnation is also worth naming as a documentation artifact: its
incremental-delta methodology (carry the score forward, patch only what a given session happened to
touch) let §3/§5 sit unexamined against genuinely new code for a full month in 2026-07, by the July
audit's own admission. That specific self-critique motivated this session's "run from scratch, don't
carry the old numbers forward" replacement.

---

## Overall Score

| Dimension | Score |
|---|---|
| Architectural Integrity | 79/100 |
| Code Quality & Craftsmanship | 65/100 |
| Efficiency & Performance | 72/100 |
| Maintainability & Evolvability | 83/100 |
| Error Handling & Resilience | 84/100 |
| Security Posture | 72/100 |
| Operational Readiness | 58/100 |
| Documentation | 68/100 |
| **TOTAL** | **581/800 (72.6%)** |

This number is **not comparable** to the previous living score (640/800, 2026-07-08) — different
methodology (from-scratch vs. incremental-delta), different evidence base (this pass ran the suite
itself, queried GitHub's live ruleset API, and hand-verified subprogram line ranges rather than
carrying forward prior citations), and a deliberately stricter read of "operationally enforced" vs.
"exists." Treat 581 as the new baseline, not a regression from 640.

---

## The Hard Truth

This is a well-engineered solo project with real discipline in the places that are hardest to fake:
the exception-handling convention is consistent, the test suite is large and genuinely green (not
carried-forward-green), the three-crate split is acyclic and well-documented, and the ADR trail
across 111 combined decisions is a better paper trail than most funded teams keep. If asked "would I
trust this at 3 AM," the answer is yes for correctness — 721/721 tests passing on a clean build is
not theater, it's the actual floor.

The uncomfortable parts are not about correctness; they're about what nothing is currently forcing.
Nothing on GitHub stops a change that breaks `make check` from reaching `sdata`'s `main`, and
sdata-core's PR requirement can be satisfied by the same person opening and merging their own PR
with zero reviews and a red CI run — the safety net that exists is entirely the maintainer's own
memory and habit, which is exactly the kind of thing that degrades quietly under time pressure and
leaves no trace when it does (a pattern this same session's Feynman audit already caught once, for
this exact ecosystem, a few hours before this report was run). And a document sitting in `doc/`
right now describes throughput numbers for a version of this software that stopped existing five
months and thirty releases ago, with nothing in the repository's own process flagging that it had
gone stale — the "keep docs current" discipline that works for `design.md`/`adrs.md`/`README.md`
simply doesn't extend to the performance doc, and nobody noticed until an adversarial pass went
looking.

---

## Appendix: Evidence Log

| Finding | Location | Evidence |
|---|---|---|
| Acyclic 3-crate dependency graph | `alr show --tree` (sdata) | sdata_core is the only path pin; sdata-core's own deps (zipada/xmlada/mathpaqs/ada_sqlite3) import nothing back |
| No lexer/AST/parser leakage into sdata-core | `sdata-core/src/*.ads` | `grep -l "Token_Kind\|Statement_Kind"` → 0 files |
| `ada_sqlite3` 0.1.1 documented leak workaround | `sdata-core/src/sdata_core-table.adb` (Backing_Store.Finalize) | REVISIT comment; `alire.toml` comment "the only published version" |
| `Execute_TRANSPOSE` 372 lines | `sdata-core/src/sdata_core-commands.adb:1289-1661` | `grep -n "procedure Execute_TRANSPOSE\|end Execute_TRANSPOSE"` |
| `Execute_AGGREGATE` 360 lines | `sdata-core/src/sdata_core-commands.adb:909-1269` | same method |
| `Stmt_USE` case arm 610 lines | `src/sdata-interpreter-execute_declarative.adb:23-632` | `grep -n "when Stmt_"` → next arm (`Stmt_SAVE`) at line 633 |
| `Execute_Tables` decomposition | `src/sdata-interpreter-execute_tables.adb` | `grep -n "^   procedure\|^   function"` → ~20 nested named subprograms across 1565 lines |
| `Parse_Expression` 495 lines | `sdata-core/src/sdata_core-evaluator.adb:777-1272` | direct grep of matching `function`/`end` pair |
| `SData_Main` 550 lines / cyclomatic 81 (ceiling 85) | `src/sdata_main.adb:38-588`; `scripts/check-complexity.sh` output | direct grep; live tool run this session |
| Zero TODO/FIXME/HACK/XXX in src/ | both crates' `src/` | `grep -rnE "TODO|FIXME|HACK|XXX"` → 0 hits |
| 18 genuine exception handlers, 17 cleanup-then-raise, 1 bare catch-all | both crates' `.adb` | manual read of all 18 (`sdata_core-io.adb:43` is the exception) |
| `Script_Error` used 168× across both crates | `sdata.ads:8`, `sdata_core.ads:28` | `grep -rn "Script_Error" src/*.adb sdata-core/src/*.adb \| wc -l` |
| All 721 integration tests + unit suites pass | `make check`, this session | second, uncontaminated run; first run's 4 `exit 126` failures traced to this session's own concurrent build and reproduced clean standalone |
| No coverage instrumentation | `Makefile`, `.github/workflows/*.yml` | `grep -rn "gnatcov\|gcov"` → 0 hits |
| sdata has no branch protection / ruleset | GitHub API | `gh api repos/jlries61/sdata/rulesets` → `[]` |
| sdata-core's ruleset requires PR but 0 reviews, no required status checks | GitHub API | `gh api repos/jlries61/sdata-core/rulesets/16766300` |
| `doc/performance_assessment.md` stale (v0.6.1, 2026-04-24, vs. current v0.37.0) | `doc/performance_assessment.md` header | direct read |
| `doc/threat_model.md` missing MISSING=/TYPES= coverage | `doc/threat_model.md` | `grep -ni "MISSING\|TYPES="` → no relevant hits; ADR-083/084 postdate the doc |
| `design.md`/`adrs.md`/`README.md`/man page all same-day current | `git log -1 --format=%ai -- <file>` | all four dated 2026-09-26 |
