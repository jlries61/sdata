# SData Threat Model

**Version:** 0.9.7 | **Date:** 2026-06-09 | **Status:** Current

*Refreshed for the three-crate split (v0.8.0, ADRs 039–043) and the input
surface added since v0.6.13: multi-dataset `USE` / merge modes, transient
tables, per-dataset/per-target `KEEP`/`DROP`/`RENAME` options, multi-target
`SAVE`, and `RENAME` type conversion (ADR-044). Internal file references are
updated to their post-split locations.*

---

## 1. System Description

SData is a single-process CLI interpreter for tabular statistical data,
compiled to a native binary and run under the account of the invoking user.
It has no network interface, no daemon mode, no authentication layer, and no
multi-user state. It reads scripts and data files, manipulates an in-memory
table (with optional SQLite spill to a temp file), and writes results to the
filesystem or stdout.

Since v0.8.0 the data layer, expression evaluator, and file I/O live in a shared
Alire library, **`sdata-core`**, consumed by both this interpreter and the
sister `data-vandal` application (ADR-039). The split does not change the trust
boundary — every consumer is still a single-process CLI under the invoking
account — but internal file references below use the `sdata_core-*` names where
the code now lives. data-vandal carries its own threat considerations; this
document covers the `sdata` interpreter.

**Out of scope for this document:**
- The host operating system and its own access controls
- The security of the tools invoked by SYSTEM/SHELL (those tools carry their
  own threat models)
- Supply-chain security of Ada library dependencies (Zip-Ada, XML-Ada,
  MathPaqs, ada_sqlite3)
- The `data-vandal` application (separate consumer of `sdata-core`)

---

## 2. Assets

| Asset | Description | Owner |
|---|---|---|
| Input data files | CSV, ODF, OOXML datasets read by SData | Operator |
| Output data files | CSV, ODF, OOXML files written by SAVE/WRITE | Operator |
| Host filesystem access | Read/write within the OS account's permissions | OS |
| SQLite temp file | On-disk backing store for large tables; deleted on exit | SData |
| OS account permissions | The ambient privilege of the running process | OS |

SData has no secrets of its own: no credentials, no tokens, no private keys.

---

## 3. Trust Model

**The OS account is the security boundary.**

SData grants the script author the same trust as the account running the
process. A script can do anything the OS account can do — read files, write
files, execute shell commands — because that is the intended design. This is
the same model used by every comparable scripting and data analysis tool:
`make`, `awk`, R (`system()`), Python (`subprocess`), SAS (`X` statement).

**Consequences:**

- A script supplied by a trusted analyst running under a restricted analyst
  account is fine.
- A script from an untrusted source running under a privileged account is a
  risk — not a SData defect, but an operator configuration problem. The
  operator should use a restricted account, not a restricted tool.

**Opt-in restrictions** for operators who need a tighter boundary:

| Flag | Effect | ADR |
|---|---|---|
| `--noshell` | Disables SYSTEM and SHELL statements entirely | ADR-031 |
| `--nosubmit` | Disables SUBMIT (external script loading) | ADR-032 |

When running as root (POSIX) or SYSTEM (Windows), `--noshell` and
`--nosubmit` are **automatically enforced** regardless of flags (ADR-033).

---

## 4. Attack Surface

| Input | Trust level | Entry point | Notes |
|---|---|---|---|
| `.cmd` / `.sdata` script | Operator-controlled | Parser → Interpreter | Full language access |
| CSV file (USE / WRITE) | Data — untrusted field values | `SData_Core.CSV`, `SData_Core.File_IO.CSV` | Column names enter SQLite DDL |
| ODF file (USE / WRITE) | Data — untrusted XML/Zip | `SData_Core.File_IO.ODF` | XML-Ada DOM parser |
| OOXML file (USE / WRITE) | Data — untrusted XML/Zip | `SData_Core.File_IO.OOXML` | XML-Ada DOM + Zip-Ada |
| Multi-dataset USE / merge | Script-controlled combination | `SData.Merge`, `SData.Transient_Table` | `/BY`, `/APPEND`, `/JOIN`, `/INTERLEAVE`; in-memory transient tables (do **not** spill) |
| Per-dataset / per-target options | Script-controlled names | `SData.Transient_Table` (`Apply_Rename`/`Keep`/`Drop`) | `KEEP=`/`DROP=`/`RENAME=`/`IN=` on USE and SAVE; RENAME-derived names reach the table |
| SYSTEM / SHELL argument | Script-controlled string | `sdata_core-system.adb` | Passed to `/bin/sh -c` |
| SUBMIT path | Script-controlled string | Interpreter SUBMIT handler | Resolved via FPATH |
| `-m` / `OPTIONS MAXINTAB` | Operator CLI / script | `sdata_core-table.adb` | Controls spill threshold (global table only) |
| SQLite temp file path | Process-local | `sdata_core-table.adb` | `/tmp/sdata_XXXXXX.db` |

---

## 5. Threats and Mitigations (STRIDE)

### 5.1 Spoofing

**Not applicable.** SData has no authentication layer and makes no identity
claims on behalf of users.

---

### 5.2 Tampering

#### T1 — SQL injection via CSV column names *(Mitigated)*

**Threat:** A CSV file with column names containing SQL metacharacters
(`"`, `'`, `]`, `--`, `;`) could corrupt or inject into the SQLite DDL/DML
statements used to persist the spilled table. Since v0.9.x, such names can also
be *produced* by a script — a `RENAME=(old=new)` option (ADR-044) can set a
column name to an arbitrary string, which is installed into the global table and
reaches the same DDL path on spill.

**Mitigation:** The `Sql_Id` helper in `sdata_core-table.adb` double-brackets all
`]` characters (`]` → `]]`) at every DDL/DML construction site. This is the
standard SQLite identifier-quoting convention using `[name]` delimiters. It is
applied uniformly to every column name regardless of origin (CSV header, RENAME
target, or array auto-detection), so RENAME-derived names inherit the same
protection. Transient tables (the merge/option-projection intermediates) never
touch SQLite — they are pure in-memory structures — so they add no injection
surface. **Commit 456d1e0.**

**Residual risk:** None for SQL injection. Column names that survive quoting are
stored verbatim; they are not further evaluated. (A future quoted-identifier
feature — design deferred — would add a third source of arbitrary column names
referenced from scripts; it must route through `Sql_Id` on the same path. Noted
here so the feature is evaluated against this threat before it ships.)

---

#### T2 — Malformed Zip archive in ODF / OOXML *(Partially mitigated)*

**Threat:** A crafted `.ods` or `.xlsx` file with a malformed Zip structure
could trigger unexpected behaviour in the Zip-Ada extraction layer.

**Mitigation:** `Zip.Entry_name_not_found` is caught for optional entries
(`sharedStrings.xml`, `workbook.xml`, `workbook.xml.rels`); the parsers
raise `Script_Error` for corrupt mandatory entries, which halts the data
step cleanly. **Commit 781d56f.**

**Residual risk:** Deep Zip-Ada parser state on a highly crafted archive has
now been covered by corpus regression (`bin/ods_fuzz_driver`,
`bin/xlsx_fuzz_driver`; 9 seed files; `make fuzz-corpus`). Full
coverage-guided fuzzing with AFL++ is not continuous — the corpus seeds
exercise known-bad inputs but may miss novel mutation paths.

---

#### T3 — Recursive script loop consuming disk via WRITE *(Accepted)*

**Threat:** A script that calls SUBMIT on itself (directly or via a chain)
with a WRITE statement in the loop body could exhaust disk space.

**Mitigation:** `--nosubmit` prevents SUBMIT. No runtime loop-depth limit
or disk-quota check exists inside SData; the OS account's disk quota or
filesystem limits are the effective guard.

**Residual risk:** Accepted. Enforcing a loop depth or output-size limit
would break legitimate use (e.g., iterative refinement scripts) and is
outside the tool's trust model.

---

### 5.3 Repudiation

**Not applicable.** SData does not claim to provide an audit trail. Script
execution leaves no log by default; `--debug` emits a trace to stderr if the
operator requests it.

---

### 5.4 Information Disclosure

#### I1 — SQLite temp file left on disk after crash *(Mitigated)*

**Threat:** The SQLite backing store (`/tmp/sdata_XXXXXX.db`) contains a
copy of the in-memory dataset. If the process exits abnormally (kill -9,
power loss), the file may persist with the dataset content.

**Mitigation:** Signal handlers for SIGTERM and SIGINT delete the temp file
before exit. **ADR-025.** The `Ada.Finalization.Limited_Controlled`
`Finalize` on the `Backing_Store` record also deletes it on normal
termination including unhandled exceptions.

**Residual risk:** SIGKILL and power loss cannot be caught. The temp file
uses a unique name (`mkstemp`-equivalent); it is not world-readable by
default on standard Linux/macOS umask settings.

---

#### I2 — No credential exposure *(N/A)*

SData stores no passwords, tokens, or private keys. It reads and writes data
files but does not handle authentication material.

---

### 5.5 Denial of Service

#### D1 — Resource exhaustion via crafted data file *(Partially mitigated)*

**Threat:** A crafted CSV or ODF/OOXML file with a very large number of
columns, rows, or very long field values could exhaust available memory or
processing time.

**Mitigation:** `-m` / `OPTIONS MAXINTAB` caps the in-memory segment size in
cells (rows × columns, **ADR-034**; default 50 000 000 cells). Above the
threshold, rows are spilled to SQLite and the in-memory footprint is bounded.
For file parsing, no per-row or per-column cell limit is enforced during the
initial read — the limit applies to the in-memory table after loading.

**Residual risk:** A file with millions of rows and thousands of columns
could cause significant wall-clock time before the spill threshold kicks in.
No per-file size or column-count cap exists. Considered acceptable for the
single-user CLI context.

---

#### D2 — SYSTEM / SHELL blocking indefinitely *(Mitigated)*

**Threat:** A SYSTEM or SHELL statement that hangs (waiting on a network
mount, stalled subprocess, or deadlocked pipeline) blocks the SData process
indefinitely in batch mode.

**Mitigation:** `OPTIONS SHELLTIMEOUT n` and `--shell-timeout=N` set a
per-command wall-clock timeout (default 300 s in batch mode, unlimited in
interactive mode). Implementation uses `GNAT.OS_Lib.Non_Blocking_Spawn` +
0.5 s poll loop + `Kill` + `Wait_Process`. **ADR-037, commits 2d57654 /
3ca764f.**

**Residual risk:** In interactive mode (`--shell-timeout=0`) there is no
timeout by default, which is intentional (`SYSTEM "bash"` should not time
out at the REPL).

---

#### D3 — Infinite loop in script *(Accepted)*

**Threat:** A WHILE or FOR loop that never terminates consumes CPU
indefinitely.

**Mitigation:** None inside SData. The OS scheduler, `timeout(1)` at the
shell invocation level, or Ctrl-C are the intended mitigations.

**Residual risk:** Accepted. A loop-execution timeout would break legitimate
long-running statistical computations. BREAK / BREAK WHEN provides a
language-level escape mechanism (**ADR-029**).

---

#### D4 — Merge amplification and unbounded transient memory *(Partially mitigated)*

**Threat:** Two surfaces added with the merge feature can amplify memory or
output beyond the input size:

1. **`/JOIN` Cartesian product.** A match-join produces, for each BY key, the
   cross product of the contributing rows. A BY group with *n* rows in one input
   and *m* in another yields *n×m* output rows, so modest inputs can produce a
   very large result (`SData.Merge` `Combine_Join`, `sdata-merge.adb:557`).
2. **In-memory transient tables.** Multi-dataset `USE`, merge, and option
   projection build `SData.Transient_Table` intermediates that are **pure
   in-memory and never spill to SQLite**. The `-m` / `OPTIONS MAXINTAB`
   threshold bounds only the *global* table; a large merge can hold several
   full-size transient copies simultaneously, above that bound.

**Mitigation:** `/JOIN` emits a warning when a group's product exceeds
`OPTIONS JOIN_WARN_THRESHOLD` (`sdata-merge.adb:561,621`) — a heads-up, not a
hard cap. Transient peak memory is otherwise governed only by the OS account's
limits (`ulimit`, cgroup).

**Residual risk:** Accepted for the single-user CLI context, consistent with D1.
`/JOIN` output and transient peak memory are not hard-capped; operators running
untrusted scripts should cap process memory at the OS level and/or set a low
`JOIN_WARN_THRESHOLD`. A future enhancement could spill transient tables or add a
hard join cap.

---

### 5.6 Elevation of Privilege

#### E1 — SYSTEM / SHELL executing arbitrary OS commands *(Accepted by design)*

**Threat:** A script can execute any OS command with SYSTEM or SHELL, subject
only to the ambient permissions of the running account.

**Mitigation:** This is the intended design (see §3). `--noshell` disables
it for operators who need containment. Automatically enforced when running
as root / SYSTEM (ADR-033). **ADR-031.**

**Residual risk:** Accepted. Sandboxing, allowlisting, and metacharacter
escaping are all won't-fix (ADR-031). The correct mitigation is to run
SData under a restricted OS account, not to restrict the tool.

---

#### E2 — SUBMIT path traversal *(Accepted by design)*

**Threat:** A SUBMIT statement in a script can reference any path reachable
from the running account, including `../../etc/passwd`-style traversal of
`FPATH_*` base directories.

**Mitigation:** `--nosubmit` disables SUBMIT. Enforced when running as root
/ SYSTEM (ADR-033). Path traversal checking inside SUBMIT is won't-fix:
enforcing it would require defining a sandbox boundary that the operator
already controls at the OS level. **ADR-032.**

**Residual risk:** Accepted. Operators running scripts from untrusted sources
should use `--nosubmit`.

---

## 6. Risk Summary

| ID | Threat | Likelihood | Impact | Status |
|---|---|---|---|---|
| T1 | SQL injection via CSV / RENAME column names | Low | Medium | **Mitigated** (456d1e0; `Sql_Id` applies to all name origins) |
| T2 | Malformed Zip in ODF / OOXML | Low | Low–Medium | **Mitigated**; corpus regression via `ods_fuzz_driver` / `xlsx_fuzz_driver` |
| T3 | Recursive SUBMIT + WRITE disk exhaustion | Very low | Low | **Accepted** (`--nosubmit` opt-in) |
| I1 | SQLite temp file on disk after crash | Low | Low | **Mitigated** (signal handlers + Finalize) |
| D1 | Resource exhaustion via crafted file | Low | Medium | **Partially mitigated** (`-m` spill threshold) |
| D2 | SYSTEM / SHELL blocking | Low | Low | **Mitigated** (ADR-037 timeout) |
| D3 | Infinite loop in script | Very low | Low | **Accepted** (OS-level mitigation) |
| D4 | Merge amplification (`/JOIN`) and unbounded transient memory | Low | Medium | **Partially mitigated** (`JOIN_WARN_THRESHOLD` warning; OS memory limits) |
| E1 | SYSTEM / SHELL arbitrary command execution | Medium (untrusted scripts) | High | **Accepted by design** (`--noshell` opt-in) |
| E2 | SUBMIT path traversal | Low | Medium | **Accepted by design** (`--nosubmit` opt-in) |

---

## 7. Known Gaps

| Gap | Notes |
|---|---|
| ~~ODF / OOXML fuzz coverage~~ | **Closed 2026-05-14:** `bin/ods_fuzz_driver` and `bin/xlsx_fuzz_driver` feed arbitrary files through `Parse_ODF` / `Parse_OOXML` using AFL++ `@@` file-path convention. Seed corpus: 4 ODS + 5 XLSX files in `tests/fuzz_corpus/ods/` and `tests/fuzz_corpus/xlsx/`; `make fuzz-corpus` runs corpus regression for all four drivers. |
| ~~No per-file size cap during CSV read~~ | **Resolved 2026-05-14 (ce037be):** `Add_Row` in `sdata_core-table.adb` already spills in-memory segments to SQLite (batched inserts) whenever `Max_Table_Cells` is reached, then continues. `Fetch_From_Disk` reads segments back on demand. For the streaming UTF-8/ASCII path the full file is always read; no truncation occurs. |
| No script execution timeout | A WHILE loop that iterates for hours is not constrained. This is by design but documented here for completeness. |
| ~~No fuzz coverage of the merge / RENAME surface~~ | **Closed 2026-06-10** (standards-review remediation #7, fuzz half): `bin/merge_fuzz_driver` derives 2–4 transient tables (typed columns, byte-derived rows) with a RENAME map from stdin and exercises `Transient_Table.Apply_Rename` / `Sort_By` and every `SData.Merge.Combine_*` combiner (Positional / Match / Interleave / Join / Append). Seed corpus: 7 files in `tests/fuzz_corpus/merge/`, plus merge/RENAME syntax seeds under `tests/fuzz_corpus/script/`; wired into `make fuzz-corpus` (CI). |
| No transient-table spill | Transient merge/projection intermediates are in-memory only and not bounded by `-m` (see D4). |
| No formal SAST | `gnatcheck.rules` with two rules (`Recursive_Subprograms`, `Too_Many_Parameters:8`) and `make gnatcheck` target exist; intentional exceptions carry in-source `pragma Annotate` exemptions. `gnatcheck` is NOT run in CI — available in Ubuntu's `asis-programs` package (not in `gnat`); not found on Debian or openSUSE. `make gnatcheck` available for manual use on Ubuntu hosts. CodePeer (commercial) has not been run. AFL++ corpus regression runs in CI; full coverage-guided fuzzing is not continuous. |

---

## 8. Deployment Recommendations

For operators running SData in pipeline or multi-tenant environments:

1. **Run under a restricted account.** Grant only the filesystem access the
   scripts genuinely need. This is the primary mitigation for E1 and E2.
2. **Use `--noshell --nosubmit`** when processing scripts from untrusted
   sources. These flags together give the most restricted execution environment
   SData provides.
3. **Set a shell timeout** for unattended batch runs:
   `--shell-timeout=60` prevents a hung SYSTEM command from stalling a
   pipeline overnight.
4. **Pin input file sizes** at the pipeline level (e.g. OS file-size quotas
   or a `wc -l` pre-check) if resource exhaustion from crafted CSV is a
   concern. SData's `-m` threshold bounds memory but not initial parse time.
5. **Cap process memory and constrain joins** for untrusted scripts that may
   merge datasets. `-m` bounds only the global table, not the in-memory
   transient intermediates used by merges and option projection (D4). Set an OS
   memory limit (`ulimit -v`, a cgroup) and a low `OPTIONS JOIN_WARN_THRESHOLD`
   to surface runaway `/JOIN` Cartesian products early.
