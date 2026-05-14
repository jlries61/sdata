# SData Threat Model

**Version:** 0.6.13 | **Date:** 2026-05-14 | **Status:** Current

---

## 1. System Description

SData is a single-process CLI interpreter for tabular statistical data,
compiled to a native binary and run under the account of the invoking user.
It has no network interface, no daemon mode, no authentication layer, and no
multi-user state. It reads scripts and data files, manipulates an in-memory
table (with optional SQLite spill to a temp file), and writes results to the
filesystem or stdout.

**Out of scope for this document:**
- The host operating system and its own access controls
- The security of the tools invoked by SYSTEM/SHELL (those tools carry their
  own threat models)
- Supply-chain security of Ada library dependencies (Zip-Ada, XML-Ada,
  MathPaqs, ada_sqlite3)

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
| CSV file (USE / WRITE) | Data — untrusted field values | `SData.CSV`, `SData.File_IO.CSV` | Column names enter SQLite DDL |
| ODF file (USE / WRITE) | Data — untrusted XML/Zip | `SData.File_IO.ODF` | XML-Ada DOM parser |
| OOXML file (USE / WRITE) | Data — untrusted XML/Zip | `SData.File_IO.OOXML` | XML-Ada DOM + Zip-Ada |
| SYSTEM / SHELL argument | Script-controlled string | `sdata-system.adb` | Passed to `/bin/sh -c` |
| SUBMIT path | Script-controlled string | Interpreter SUBMIT handler | Resolved via FPATH |
| `-m` / `OPTIONS MAXINTAB` | Operator CLI / script | `sdata-table.adb` | Controls spill threshold |
| SQLite temp file path | Process-local | `sdata-table.adb` | `/tmp/sdata_XXXXXX.db` |

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
statements used to persist the spilled table.

**Mitigation:** The `Sql_Id` helper in `sdata-table.adb` double-brackets all
`]` characters (`]` → `]]`) at every DDL/DML construction site. This is the
standard SQLite identifier-quoting convention using `[name]` delimiters.
**Commit 456d1e0.**

**Residual risk:** None for SQL injection. Column names that survive
quoting are stored verbatim; they are not further evaluated.

---

#### T2 — Malformed Zip archive in ODF / OOXML *(Partially mitigated)*

**Threat:** A crafted `.ods` or `.xlsx` file with a malformed Zip structure
could trigger unexpected behaviour in the Zip-Ada extraction layer.

**Mitigation:** `Zip.Entry_name_not_found` is caught for optional entries
(`sharedStrings.xml`, `workbook.xml`, `workbook.xml.rels`); the parsers
raise `Script_Error` for corrupt mandatory entries, which halts the data
step cleanly. **Commit 781d56f.**

**Residual risk:** Deep Zip-Ada parser state on a highly crafted archive has
not been fuzz-tested. The fuzz drivers (`bin/csv_fuzz_driver`,
`bin/parser_fuzz_driver`) do not cover the ODF/OOXML Zip path. This is a
known gap (see §7).

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
| T1 | SQL injection via CSV column names | Low | Medium | **Mitigated** (456d1e0) |
| T2 | Malformed Zip in ODF / OOXML | Low | Low–Medium | **Partially mitigated**; ODF/OOXML path not fuzz-tested |
| T3 | Recursive SUBMIT + WRITE disk exhaustion | Very low | Low | **Accepted** (`--nosubmit` opt-in) |
| I1 | SQLite temp file on disk after crash | Low | Low | **Mitigated** (signal handlers + Finalize) |
| D1 | Resource exhaustion via crafted file | Low | Medium | **Partially mitigated** (`-m` spill threshold) |
| D2 | SYSTEM / SHELL blocking | Low | Low | **Mitigated** (ADR-037 timeout) |
| D3 | Infinite loop in script | Very low | Low | **Accepted** (OS-level mitigation) |
| E1 | SYSTEM / SHELL arbitrary command execution | Medium (untrusted scripts) | High | **Accepted by design** (`--noshell` opt-in) |
| E2 | SUBMIT path traversal | Low | Medium | **Accepted by design** (`--nosubmit` opt-in) |

---

## 7. Known Gaps

| Gap | Notes |
|---|---|
| ODF / OOXML fuzz coverage | `bin/csv_fuzz_driver` and `bin/parser_fuzz_driver` do not reach the Zip-Ada or XML-Ada paths. A dedicated `ods_fuzz_driver` / `xlsx_fuzz_driver` that feeds raw file bytes through `Parse_ODF` / `Parse_OOXML` would close this. |
| No per-file size cap during CSV read | Very large CSV files are read fully into memory before the `-m` cell limit applies. A streaming row cap during `Parse_CSV` would bound memory for pathological inputs. |
| No script execution timeout | A WHILE loop that iterates for hours is not constrained. This is by design but documented here for completeness. |
| No formal SAST | `gnatcheck.rules` with two rules (`Recursive_Subprograms`, `Too_Many_Parameters:8`) and `make gnatcheck` target exist; intentional exceptions carry in-source `pragma Annotate` exemptions. `gnatcheck` is NOT run in CI — unavailable outside Debian/Ubuntu `gnat` packages; absent on openSUSE. `make gnatcheck` available for manual use on Debian-derivative hosts. CodePeer (commercial) has not been run. AFL++ corpus regression runs in CI; full coverage-guided fuzzing is not continuous. |

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
