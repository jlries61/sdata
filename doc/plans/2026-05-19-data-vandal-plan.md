# data-vandal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract a shared `sdata-core` library, remove VANDALIZE from SData, and build the
standalone `data-vandal` interpreter that supports USE / FPATH / OUTPUT / SELECT / KEEP / DROP /
ARRAY / RUN / VANDALIZE.

**Architecture:** Three sibling crates under `~/Develop/`: `sdata-core` (Alire library, path
dependency), `sdata` (refactored to depend on sdata-core; VANDALIZE removed), and `data-vandal`
(new application crate with its own lexer/AST/parser/interpreter). The shared code — data layer,
evaluator, and command execution procedures — lives in sdata-core; each application owns its
complete token set and grammar.

**Tech Stack:** Ada 2012, GNAT (via Alire), Alire package manager, make for test orchestration.
All existing sdata dependencies (zipada, xmlada, mathpaqs, ada_sqlite3) move to sdata-core.

---

## Phase A — sdata-core Library

---

### Task 1: Bootstrap sdata-core Project

**Files:**
- Create: `~/Develop/sdata-core/alire.toml`
- Create: `~/Develop/sdata-core/sdata_core.gpr`
- Create: `~/Develop/sdata-core/src/sdata_core.ads`

- [ ] **Step 1: Create directory**

```bash
mkdir -p ~/Develop/sdata-core/src
```

- [ ] **Step 2: Write `alire.toml`**

```toml
name = "sdata_core"
description = "Shared data-layer and evaluator library for sdata and data-vandal"
version = "0.1.0"

authors = ["John L. Ries"]
maintainers = ["John L. Ries <john@theyarnbard.com>"]
licenses = "GPL-3.0-only"

[[depends-on]]
zipada = "^61.0.0"

[[depends-on]]
xmlada = "^26.0.0"

[[depends-on]]
mathpaqs = "^20260205.0.0"

[[depends-on]]
ada_sqlite3 = "^0.1.1"
```

- [ ] **Step 3: Write `sdata_core.gpr`**

```ada
with "zipada";
with "xmlada_dom";
with "xmlada_input";
with "mathpaqs";
with "ada_sqlite3";

library project SData_Core is
   for Library_Name use "sdata_core";
   for Library_Kind use "static";
   for Languages use ("Ada", "C");
   for Source_Dirs use ("src/**");
   for Object_Dir use "obj";
   for Library_Dir use "lib";

   package Compiler is
      for Default_Switches ("Ada") use
         ("-gnat2012", "-gnatwa", "-gnatwl", "-gnatwu", "-g", "-O2");
   end Compiler;
end SData_Core;
```

- [ ] **Step 4: Write `src/sdata_core.ads`**

```ada
--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later

--  Root package for the sdata-core shared library.
package SData_Core is
end SData_Core;
```

- [ ] **Step 5: Verify empty library builds**

```bash
cd ~/Develop/sdata-core && alr build
```

Expected: build succeeds with no source files to compile (just the root package).

- [ ] **Step 6: Commit**

```bash
cd ~/Develop/sdata-core && git init && git add -A
git commit -m "feat: bootstrap sdata-core library project"
```

---

### Task 2: Move Data-Layer Packages (Table, Values, Variables, Statistics, CSV)

This task establishes the package-rename pattern used by all subsequent move tasks.
Each package `SData.X` becomes `SData_Core.X`; each file `sdata-x.ads/adb` becomes
`sdata_core-x.ads/adb`.

**Files to move from `sdata/src/` → `sdata-core/src/`:**
- `sdata-table.ads/adb` → `sdata_core-table.ads/adb` (package SData_Core.Table)
- `sdata-values.ads/adb` → `sdata_core-values.ads/adb` (package SData_Core.Values)
- `sdata-variables.ads/adb` → `sdata_core-variables.ads/adb` (package SData_Core.Variables)
- `sdata-statistics.ads/adb` → `sdata_core-statistics.ads/adb` (package SData_Core.Statistics)
- `sdata-csv.ads/adb` → `sdata_core-csv.ads/adb` (package SData_Core.CSV)

**Files to modify in `sdata/`:**
- `sdata.gpr` — add `with "sdata_core"`, remove direct dependency lines for moved packages
- `alire.toml` — add path pin for sdata-core
- Every `.ads`/`.adb` in `sdata/src/` that `with`s a moved package — update the package name

- [ ] **Step 1: Copy and rename files to sdata-core**

```bash
cd ~/Develop/sdata/src
for pkg in table values variables statistics csv; do
  cp sdata-${pkg}.ads ~/Develop/sdata-core/src/sdata_core-${pkg}.ads
  cp sdata-${pkg}.adb ~/Develop/sdata-core/src/sdata_core-${pkg}.adb
done
```

- [ ] **Step 2: Rename package declarations in all five new files**

For each file in `~/Develop/sdata-core/src/`, replace the package prefix. Example for table:

```bash
cd ~/Develop/sdata-core/src
sed -i 's/\bpackage SData\.Table\b/package SData_Core.Table/g' \
    sdata_core-table.ads sdata_core-table.adb
sed -i 's/\bpackage body SData\.Table\b/package body SData_Core.Table/g' \
    sdata_core-table.adb
sed -i 's/\bwith SData\.Values\b/with SData_Core.Values/g' \
    sdata_core-table.ads sdata_core-table.adb
sed -i 's/\bSData\.Values\b/SData_Core.Values/g' \
    sdata_core-table.ads sdata_core-table.adb
```

Repeat this pattern for each of the five packages, updating all cross-references
(e.g., `sdata_core-variables.adb` references `SData.Table` — update to `SData_Core.Table`,
and `SData.Values` → `SData_Core.Values`, and `SData.Statistics` → `SData_Core.Statistics`).

Use the following command to find all internal cross-references that need updating:

```bash
grep -rn '\bSData\.' ~/Develop/sdata-core/src/
```

All occurrences of `SData.Table`, `SData.Values`, `SData.Variables`, `SData.Statistics`,
`SData.CSV` must be replaced with their `SData_Core.*` equivalents. `SData.Config`,
`SData.File_IO`, etc. remain as-is for now (moved in later tasks).

- [ ] **Step 3: Delete originals from sdata**

```bash
cd ~/Develop/sdata/src
rm sdata-table.ads sdata-table.adb \
   sdata-values.ads sdata-values.adb \
   sdata-variables.ads sdata-variables.adb \
   sdata-statistics.ads sdata-statistics.adb \
   sdata-csv.ads sdata-csv.adb
```

- [ ] **Step 4: Add path pin to sdata**

In `~/Develop/sdata/alire.toml`, append:

```toml
[[depends-on]]
sdata_core = "*"

[[pins]]
sdata_core = { path = "../sdata-core" }
```

- [ ] **Step 5: Update sdata.gpr**

Replace the current `~/Develop/sdata/sdata.gpr` with:

```ada
with "sdata_core";

project SData is
   for Languages use ("Ada", "C");
   for Source_Dirs use ("src/**", "tests");
   for Object_Dir use "obj";
   for Exec_Dir use "bin";
   for Main use ("sdata_main.adb", "csv_unit_test.adb", "sdata_unit_test.adb",
                 "evaluator_unit_test.adb", "file_io_unit_test.adb",
                 "interpreter_unit_test.adb",
                 "csv_fuzz_driver.adb", "parser_fuzz_driver.adb",
                 "ods_fuzz_driver.adb", "xlsx_fuzz_driver.adb");

   package Compiler is
      for Default_Switches ("Ada") use
         ("-gnat2012", "-gnatwa", "-gnatwl", "-gnatwu", "-g", "-O2");
   end Compiler;

   package Builder is
      for Default_Switches ("Ada") use ("-g");
      for Executable ("sdata_main.adb")             use "sdata";
      for Executable ("csv_unit_test.adb")          use "csv_unit_test";
      for Executable ("sdata_unit_test.adb")        use "sdata_unit_test";
      for Executable ("evaluator_unit_test.adb")    use "evaluator_unit_test";
      for Executable ("file_io_unit_test.adb")      use "file_io_unit_test";
      for Executable ("interpreter_unit_test.adb")  use "interpreter_unit_test";
      for Executable ("csv_fuzz_driver.adb")        use "csv_fuzz_driver";
      for Executable ("parser_fuzz_driver.adb")     use "parser_fuzz_driver";
      for Executable ("ods_fuzz_driver.adb")        use "ods_fuzz_driver";
      for Executable ("xlsx_fuzz_driver.adb")       use "xlsx_fuzz_driver";
   end Builder;
end SData;
```

- [ ] **Step 6: Update with-clauses throughout sdata/src**

```bash
cd ~/Develop/sdata/src
find . -name "*.ads" -o -name "*.adb" | xargs sed -i \
  -e 's/\bwith SData\.Table\b/with SData_Core.Table/g' \
  -e 's/\bwith SData\.Values\b/with SData_Core.Values/g' \
  -e 's/\bwith SData\.Variables\b/with SData_Core.Variables/g' \
  -e 's/\bwith SData\.Statistics\b/with SData_Core.Statistics/g' \
  -e 's/\bwith SData\.CSV\b/with SData_Core.CSV/g' \
  -e 's/\buse SData\.Table\b/use SData_Core.Table/g' \
  -e 's/\buse SData\.Values\b/use SData_Core.Values/g' \
  -e 's/\buse SData\.Variables\b/use SData_Core.Variables/g' \
  -e 's/\buse SData\.Statistics\b/use SData_Core.Statistics/g' \
  -e 's/\buse SData\.CSV\b/use SData_Core.CSV/g'
```

Then replace all qualified references:

```bash
find . -name "*.ads" -o -name "*.adb" | xargs sed -i \
  -e 's/\bSData\.Table\./SData_Core.Table./g' \
  -e 's/\bSData\.Values\./SData_Core.Values./g' \
  -e 's/\bSData\.Variables\./SData_Core.Variables./g' \
  -e 's/\bSData\.Statistics\./SData_Core.Statistics./g' \
  -e 's/\bSData\.CSV\./SData_Core.CSV./g'
```

Verify no stray references remain:

```bash
grep -rn '\bSData\.\(Table\|Values\|Variables\|Statistics\|CSV\)\b' ~/Develop/sdata/src/
```

Expected: no output.

- [ ] **Step 7: Build sdata-core and sdata**

```bash
cd ~/Develop/sdata-core && alr build
cd ~/Develop/sdata && alr build
```

Both must succeed. Fix any remaining reference errors before proceeding.

- [ ] **Step 8: Run sdata test suite**

```bash
cd ~/Develop/sdata && make check
```

Expected: all tests pass (same count as before this task).

- [ ] **Step 9: Commit both repos**

```bash
cd ~/Develop/sdata-core && git add -A
git commit -m "feat: add Table, Values, Variables, Statistics, CSV packages"

cd ~/Develop/sdata && git add -A
git commit -m "refactor: move Table/Values/Variables/Statistics/CSV to sdata-core"
```

---

### Task 3: Move I/O Packages (IO, File_IO Family)

**Files to move from `sdata/src/` → `sdata-core/src/`:**
- `sdata-io.ads/adb` → `sdata_core-io.ads/adb`
- `sdata-file_io.ads/adb` → `sdata_core-file_io.ads/adb`
- `sdata-file_io-csv.ads/adb` → `sdata_core-file_io-csv.ads/adb`
- `sdata-file_io-odf.ads/adb` → `sdata_core-file_io-odf.ads/adb`
- `sdata-file_io-ooxml.ads/adb` → `sdata_core-file_io-ooxml.ads/adb`
- `sdata-file_io-helpers.ads/adb` → `sdata_core-file_io-helpers.ads/adb`

- [ ] **Step 1: Copy files to sdata-core**

```bash
cd ~/Develop/sdata/src
cp sdata-io.ads sdata-io.adb \
   sdata-file_io.ads sdata-file_io.adb \
   sdata-file_io-csv.ads sdata-file_io-csv.adb \
   sdata-file_io-odf.ads sdata-file_io-odf.adb \
   sdata-file_io-ooxml.ads sdata-file_io-ooxml.adb \
   sdata-file_io-helpers.ads sdata-file_io-helpers.adb \
   ~/Develop/sdata-core/src/
cd ~/Develop/sdata-core/src
for f in sdata-io* sdata-file_io*; do
  mv "$f" "sdata_core${f#sdata}"
done
```

- [ ] **Step 2: Rename package declarations**

Apply the same pattern as Task 2, replacing `SData.IO` → `SData_Core.IO` and
`SData.File_IO` → `SData_Core.File_IO` (and child packages) throughout all new files.

```bash
cd ~/Develop/sdata-core/src
find . -name "sdata_core-io*" -o -name "sdata_core-file_io*" | xargs sed -i \
  -e 's/\bpackage SData\./package SData_Core./g' \
  -e 's/\bpackage body SData\./package body SData_Core./g' \
  -e 's/\bwith SData\.Table\b/with SData_Core.Table/g' \
  -e 's/\bwith SData\.Values\b/with SData_Core.Values/g' \
  -e 's/\bwith SData\.CSV\b/with SData_Core.CSV/g' \
  -e 's/\bSData\.Table\./SData_Core.Table./g' \
  -e 's/\bSData\.Values\./SData_Core.Values./g' \
  -e 's/\bSData\.CSV\./SData_Core.CSV./g'
```

Verify no stray `SData.` references remain in the moved files (references to `SData.Config`
are expected and will stay until Task 4):

```bash
grep -n '\bSData\.\(IO\|File_IO\)\b' ~/Develop/sdata-core/src/sdata_core-*.adb
```

Expected: no output.

- [ ] **Step 3: Delete originals from sdata and update references**

```bash
cd ~/Develop/sdata/src
rm sdata-io.ads sdata-io.adb \
   sdata-file_io.ads sdata-file_io.adb \
   sdata-file_io-csv.ads sdata-file_io-csv.adb \
   sdata-file_io-odf.ads sdata-file_io-odf.adb \
   sdata-file_io-ooxml.ads sdata-file_io-ooxml.adb \
   sdata-file_io-helpers.ads sdata-file_io-helpers.adb

find . -name "*.ads" -o -name "*.adb" | xargs sed -i \
  -e 's/\bwith SData\.IO\b/with SData_Core.IO/g' \
  -e 's/\bwith SData\.File_IO\b/with SData_Core.File_IO/g' \
  -e 's/\buse SData\.IO\b/use SData_Core.IO/g' \
  -e 's/\buse SData\.File_IO\b/use SData_Core.File_IO/g' \
  -e 's/\bSData\.IO\./SData_Core.IO./g' \
  -e 's/\bSData\.File_IO\./SData_Core.File_IO./g'
```

- [ ] **Step 4: Build and test**

```bash
cd ~/Develop/sdata-core && alr build
cd ~/Develop/sdata && alr build && make check
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
cd ~/Develop/sdata-core && git add -A
git commit -m "feat: add IO and File_IO packages"
cd ~/Develop/sdata && git add -A
git commit -m "refactor: move IO and File_IO family to sdata-core"
```

---

### Task 4: Move Config and Signals

**Files to move:**
- `sdata-config.ads` → `sdata_core-config.ads`
- `sdata-config-runtime.ads/adb` → `sdata_core-config-runtime.ads/adb`
- `sdata-signals.ads/adb` → `sdata_core-signals.ads/adb`

Note: `sdata-config.ads` declares `package SData.Config` which also defines `Format_Type` and
constants used throughout sdata. After the rename it becomes `package SData_Core.Config`.
Every reference to `SData.Config.*` in remaining sdata sources updates to `SData_Core.Config.*`.

- [ ] **Step 1: Copy and rename**

```bash
cp ~/Develop/sdata/src/sdata-config.ads \
   ~/Develop/sdata-core/src/sdata_core-config.ads
cp ~/Develop/sdata/src/sdata-config-runtime.ads \
   ~/Develop/sdata-core/src/sdata_core-config-runtime.ads
cp ~/Develop/sdata/src/sdata-config-runtime.adb \
   ~/Develop/sdata-core/src/sdata_core-config-runtime.adb
cp ~/Develop/sdata/src/sdata-signals.ads \
   ~/Develop/sdata-core/src/sdata_core-signals.ads
cp ~/Develop/sdata/src/sdata-signals.adb \
   ~/Develop/sdata-core/src/sdata_core-signals.adb

cd ~/Develop/sdata-core/src
sed -i \
  -e 's/\bpackage SData\.Config\b/package SData_Core.Config/g' \
  -e 's/\bpackage body SData\.Config\b/package body SData_Core.Config/g' \
  -e 's/\bpackage SData\.Signals\b/package SData_Core.Signals/g' \
  -e 's/\bpackage body SData\.Signals\b/package body SData_Core.Signals/g' \
  sdata_core-config.ads sdata_core-config-runtime.ads \
  sdata_core-config-runtime.adb sdata_core-signals.ads sdata_core-signals.adb
```

- [ ] **Step 2: Delete originals and update sdata references**

```bash
rm ~/Develop/sdata/src/sdata-config.ads \
   ~/Develop/sdata/src/sdata-config-runtime.ads \
   ~/Develop/sdata/src/sdata-config-runtime.adb \
   ~/Develop/sdata/src/sdata-signals.ads \
   ~/Develop/sdata/src/sdata-signals.adb

cd ~/Develop/sdata/src
find . -name "*.ads" -o -name "*.adb" | xargs sed -i \
  -e 's/\bwith SData\.Config\b/with SData_Core.Config/g' \
  -e 's/\bwith SData\.Signals\b/with SData_Core.Signals/g' \
  -e 's/\buse SData\.Config\b/use SData_Core.Config/g' \
  -e 's/\buse SData\.Signals\b/use SData_Core.Signals/g' \
  -e 's/\bSData\.Config\./SData_Core.Config./g' \
  -e 's/\bSData\.Signals\./SData_Core.Signals./g'
```

- [ ] **Step 3: Build and test**

```bash
cd ~/Develop/sdata-core && alr build
cd ~/Develop/sdata && alr build && make check
```

- [ ] **Step 4: Commit**

```bash
cd ~/Develop/sdata-core && git add -A
git commit -m "feat: add Config and Signals packages"
cd ~/Develop/sdata && git add -A
git commit -m "refactor: move Config and Signals to sdata-core"
```

---

### Task 5: Move Evaluator Family and Extract Expression Types

This is the most surgical move. `Expression_Kind`, `Expression`, `Expression_Access`, and
`Free_Expression` currently live in `SData.AST` (`src/ast/sdata-ast.ads/adb`). They move into
`SData_Core.Evaluator`. `SData.AST` then gains `with SData_Core.Evaluator` and references
`Expression_Access` from there.

**Files to move:**
- `src/sdata-evaluator.ads/adb` → `sdata_core-evaluator.ads/adb`
- `src/sdata-evaluator-aggregate_fns.ads/adb` → `sdata_core-evaluator-aggregate_fns.ads/adb`
- `src/sdata-evaluator-distrib_fns.ads/adb` → `sdata_core-evaluator-distrib_fns.ads/adb`
- `src/sdata-evaluator-misc_fns.ads/adb` → `sdata_core-evaluator-misc_fns.ads/adb`
- `src/sdata-evaluator-nav_fns.ads/adb` → `sdata_core-evaluator-nav_fns.ads/adb`
- `src/sdata-evaluator-numeric_fns.ads/adb` → `sdata_core-evaluator-numeric_fns.ads/adb`
- `src/sdata-evaluator-string_fns.ads/adb` → `sdata_core-evaluator-string_fns.ads/adb`

**Files to modify:**
- `src/ast/sdata-ast.ads` — remove expression types; add `with SData_Core.Evaluator`
- `src/ast/sdata-ast.adb` — remove `Free_Expression` body (now in sdata-core)

- [ ] **Step 1: Copy and rename evaluator files**

```bash
cd ~/Develop/sdata/src
for f in sdata-evaluator*.ads sdata-evaluator*.adb; do
  cp "$f" ~/Develop/sdata-core/src/"${f/sdata-/sdata_core-}"
done

cd ~/Develop/sdata-core/src
find . -name "sdata_core-evaluator*" | xargs sed -i \
  -e 's/\bpackage SData\.Evaluator\b/package SData_Core.Evaluator/g' \
  -e 's/\bpackage body SData\.Evaluator\b/package body SData_Core.Evaluator/g' \
  -e 's/\bwith SData\.Table\b/with SData_Core.Table/g' \
  -e 's/\bwith SData\.Values\b/with SData_Core.Values/g' \
  -e 's/\bwith SData\.Variables\b/with SData_Core.Variables/g' \
  -e 's/\bwith SData\.Statistics\b/with SData_Core.Statistics/g' \
  -e 's/\bwith SData\.Config\b/with SData_Core.Config/g' \
  -e 's/\bSData\.Table\./SData_Core.Table./g' \
  -e 's/\bSData\.Values\./SData_Core.Values./g' \
  -e 's/\bSData\.Variables\./SData_Core.Variables./g' \
  -e 's/\bSData\.Statistics\./SData_Core.Statistics./g' \
  -e 's/\bSData\.Config\./SData_Core.Config./g'
```

- [ ] **Step 2: Move expression types from SData.AST into SData_Core.Evaluator**

The expression types — `Expression_Kind`, `Expression`, `Expression_Access`, and
`Free_Expression` — are currently declared in `src/ast/sdata-ast.ads` and implemented in
`src/ast/sdata-ast.adb`. They must be cut from `SData.AST` and appended to the public
section of `SData_Core.Evaluator`.

Open `src/ast/sdata-ast.ads` and cut the following block (approximately lines 15–40 and
the `Free_Expression` declaration at line ~281). Paste it into
`~/Develop/sdata-core/src/sdata_core-evaluator.ads` before the `end SData_Core.Evaluator;`
line. Apply the same to the `Free_Expression` body in `src/ast/sdata-ast.adb`.

After the cut, `src/ast/sdata-ast.ads` must add at the top:

```ada
with SData_Core.Evaluator; use SData_Core.Evaluator;
```

and remove the now-absent expression type declarations. Statement fields that used
`Expression_Access` continue to compile because the type is now visible via `use`.

- [ ] **Step 3: Delete evaluator originals from sdata and update references**

```bash
cd ~/Develop/sdata/src
rm sdata-evaluator.ads sdata-evaluator.adb \
   sdata-evaluator-aggregate_fns.ads sdata-evaluator-aggregate_fns.adb \
   sdata-evaluator-distrib_fns.ads sdata-evaluator-distrib_fns.adb \
   sdata-evaluator-misc_fns.ads sdata-evaluator-misc_fns.adb \
   sdata-evaluator-nav_fns.ads sdata-evaluator-nav_fns.adb \
   sdata-evaluator-numeric_fns.ads sdata-evaluator-numeric_fns.adb \
   sdata-evaluator-string_fns.ads sdata-evaluator-string_fns.adb

find . -name "*.ads" -o -name "*.adb" | xargs sed -i \
  -e 's/\bwith SData\.Evaluator\b/with SData_Core.Evaluator/g' \
  -e 's/\buse SData\.Evaluator\b/use SData_Core.Evaluator/g' \
  -e 's/\bSData\.Evaluator\./SData_Core.Evaluator./g'
```

- [ ] **Step 4: Build sdata-core**

```bash
cd ~/Develop/sdata-core && alr build
```

Expected: builds cleanly. Fix any `SData.AST`-reference errors in the evaluator
(the evaluator originally used `SData.AST.Expression_Access`; it now owns those types).

- [ ] **Step 5: Build and test sdata**

```bash
cd ~/Develop/sdata && alr build && make check
```

- [ ] **Step 6: Commit**

```bash
cd ~/Develop/sdata-core && git add -A
git commit -m "feat: add Evaluator family; absorb Expression types from AST"
cd ~/Develop/sdata && git add -A
git commit -m "refactor: move Evaluator to sdata-core; trim expression types from AST"
```

---

### Task 6: Add Parse_Expression to SData_Core.Evaluator

`SData_Core.Evaluator.Parse_Expression` takes a `String` (expression text with no surrounding
whitespace), runs an internal mini-lexer, and returns an `Expression_Access`. Both application
parsers will call this after extracting the expression text from the input line.

**Files:**
- Modify: `~/Develop/sdata-core/src/sdata_core-evaluator.ads` — add declaration
- Modify: `~/Develop/sdata-core/src/sdata_core-evaluator.adb` — add implementation

The internal mini-lexer tokenises: identifiers, integer literals, float literals, quoted string
literals, parentheses, commas, and the operators `+`, `-`, `*`, `/`, `<`, `>`, `=`, `<=`, `>=`,
`<>`, the keywords `AND`, `OR`, `NOT`, `MOD`. This is a strict subset of SData's full lexer; the
existing expression parsing logic in `src/parser/sdata-parser.adb` is the model — port
the recursive-descent expression parser into this procedure, replacing token-stream reads
with reads from the internal string position.

- [ ] **Step 1: Add declaration to `sdata_core-evaluator.ads`**

Before the `end SData_Core.Evaluator;` line, add:

```ada
   --  Parse an expression from a plain string.  Used by application parsers
   --  after they extract the expression text from the input stream.
   --  Raises Constraint_Error with a descriptive message on syntax error.
   function Parse_Expression (Text : String) return Expression_Access;
```

- [ ] **Step 2: Implement in `sdata_core-evaluator.adb`**

Port the recursive-descent expression parser from `~/Develop/sdata/src/parser/sdata-parser.adb`.
The existing parser reads from a shared token cursor; the new version advances an index into
`Text` instead. The tree-building logic (creating `Expression` nodes for binary operators,
unary NOT, function calls, literals, identifiers) is unchanged.

Key skeleton:

```ada
function Parse_Expression (Text : String) return Expression_Access is
   Pos : Positive := Text'First;

   procedure Skip_Whitespace is
   begin
      while Pos <= Text'Last and then Text (Pos) = ' ' loop
         Pos := Pos + 1;
      end loop;
   end Skip_Whitespace;

   --  Mutual recursion: Parse_Or → Parse_And → Parse_Not →
   --  Parse_Comparison → Parse_Additive → Parse_Multiplicative → Parse_Primary
   function Parse_Or   return Expression_Access;
   function Parse_And  return Expression_Access;
   function Parse_Not  return Expression_Access;
   function Parse_Comparison return Expression_Access;
   function Parse_Additive   return Expression_Access;
   function Parse_Multiplicative return Expression_Access;
   function Parse_Primary    return Expression_Access;

   --  ... implementations follow the same recursive-descent structure
   --  as sdata-parser.adb, substituting Pos/Text for the token stream ...
begin
   Skip_Whitespace;
   return Parse_Or;
end Parse_Expression;
```

- [ ] **Step 3: Update sdata's SELECT parser to call Parse_Expression**

In `~/Develop/sdata/src/parser/sdata-parser.adb`, locate the `Stmt_SELECT_FILTER` parsing
section. After reading the `SELECT` keyword, collect all remaining tokens on the current
input line into a `String`, then call:

```ada
with SData_Core.Evaluator; use SData_Core.Evaluator;
-- ...
S.Condition := Parse_Expression (Collected_Text);
```

Remove the inline recursive-descent expression parser from `sdata-parser.adb` once
`Parse_Expression` is in place and all evaluator unit tests pass.

- [ ] **Step 4: Build and test**

```bash
cd ~/Develop/sdata-core && alr build
cd ~/Develop/sdata && alr build && make check
```

- [ ] **Step 5: Commit**

```bash
cd ~/Develop/sdata-core && git add -A
git commit -m "feat: add Parse_Expression to Evaluator (string-based, internal lexer)"
cd ~/Develop/sdata && git add -A
git commit -m "refactor: use SData_Core.Evaluator.Parse_Expression in SELECT parser"
```

---

### Task 7: Add SData_Core.Commands

`SData_Core.Commands` is a new package containing one execution procedure per shared command.
Procedures access `SData_Core.Config.Runtime` directly for interpreter state (file paths, save
settings). `Select_Filter_Expr` is added as a new variable in `SData_Core.Config.Runtime`.

**Files:**
- Create: `~/Develop/sdata-core/src/sdata_core-commands.ads`
- Create: `~/Develop/sdata-core/src/sdata_core-commands.adb`
- Modify: `~/Develop/sdata-core/src/sdata_core-config-runtime.ads` — add `Select_Filter_Expr`

- [ ] **Step 1: Add Select_Filter_Expr to SData_Core.Config.Runtime**

In `sdata_core-config-runtime.ads`, add after the existing variable declarations:

```ada
with SData_Core.Evaluator;
-- (in the package body section)
Select_Filter_Expr : SData_Core.Evaluator.Expression_Access := null;
```

- [ ] **Step 2: Write `sdata_core-commands.ads`**

```ada
--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later

with SData_Core.Evaluator;

package SData_Core.Commands is

   --  Each procedure extracts all work from the interpreter and operates
   --  on SData_Core.Config.Runtime, SData_Core.Table, and the other
   --  sdata-core package-level state.

   procedure Execute_USE    (Path : String);
   procedure Execute_SAVE   (Path : String; Fmt : SData_Core.Config.Format_Type;
                             Sheet : String; Dlm : String;
                             Header : Boolean; Overwrite : Boolean;
                             Charset : String);
   procedure Execute_FPATH  (Use_Path : String; Save_Path : String;
                             Output_Path : String; Submit_Path : String);
   procedure Execute_OUTPUT (Path : String; Fmt : SData_Core.Config.Format_Type);
   procedure Execute_SELECT (Expr : SData_Core.Evaluator.Expression_Access);
   procedure Execute_KEEP   (Names : SData_Core.Variables.Name_Array;
                             Count : Natural);
   procedure Execute_DROP   (Names : SData_Core.Variables.Name_Array;
                             Count : Natural);
   procedure Execute_ARRAY  (Group_Name : String;
                             Vars : SData_Core.Variables.Name_Array;
                             Count : Natural);
   procedure Execute_DIM    (Base_Name : String;
                             Start_Idx : Integer; End_Idx : Integer);
   procedure Execute_RUN;

end SData_Core.Commands;
```

Adjust parameter types to match the exact types used in the rest of sdata-core (check
`SData_Core.Variables` and `SData_Core.Config` for the right array/string types).

- [ ] **Step 3: Write `sdata_core-commands.adb`**

Port the implementation of each command from `~/Develop/sdata/src/sdata-interpreter.adb`
and `~/Develop/sdata/src/sdata-interpreter-execute_declarative.adb`. The handler for each
command is identifiable by its `Stmt_*` case branch. Copy the body logic verbatim,
replacing all package references that were updated in earlier tasks. `Execute_RUN` includes
the filter-map rebuild and conditional save logic currently in the `Stmt_RUN` branch of the
interpreter.

- [ ] **Step 4: Build sdata-core**

```bash
cd ~/Develop/sdata-core && alr build
```

- [ ] **Step 5: Commit**

```bash
cd ~/Develop/sdata-core && git add -A
git commit -m "feat: add Commands package with shared command execution procedures"
```

---

### Task 8: Add Register_Subscripted_Columns

**Files:**
- Modify: `~/Develop/sdata-core/src/sdata_core-variables.ads` — add declaration
- Modify: `~/Develop/sdata-core/src/sdata_core-variables.adb` — add implementation

- [ ] **Step 1: Write a failing integration test in sdata**

Create `~/Develop/sdata/tests/auto_array_detect.cmd`:

```
USE tests/data/subscripted.csv
NAMES
```

Create `~/Develop/sdata/tests/data/subscripted.csv`:

```
x(1),x(2),x(3),y
1,2,3,10
4,5,6,20
```

Create `~/Develop/sdata/tests/expected/auto_array_detect.txt` with the expected NAMES output
that shows `x` registered as an array. Run:

```bash
cd ~/Develop/sdata && make check 2>&1 | grep auto_array
```

Expected: test fails (arrays not yet auto-detected).

- [ ] **Step 2: Add declaration to `sdata_core-variables.ads`**

```ada
   --  Scan Table column names for the pattern base(n) where n is a positive
   --  integer.  For each unique base name found, register the group as a DIM
   --  array spanning the minimum and maximum n observed.  Gaps in the numeric
   --  sequence are permitted.  Call after every Execute_USE.
   procedure Register_Subscripted_Columns;
```

- [ ] **Step 3: Implement in `sdata_core-variables.adb`**

```ada
procedure Register_Subscripted_Columns is
   use SData_Core.Table;
   use Ada.Strings.Fixed;

   type Base_Range is record
      Min_Idx : Positive;
      Max_Idx : Positive;
   end record;

   package Base_Maps is new Ada.Containers.Ordered_Maps
     (Key_Type     => Ada.Strings.Unbounded.Unbounded_String,
      Element_Type => Base_Range);
   Bases : Base_Maps.Map;

   Col_Count : constant Natural := Column_Count;
begin
   --  Pass 1: find all name(n) columns and record min/max subscript per base.
   for I in 1 .. Col_Count loop
      declare
         Name : constant String := Column_Name (I);
         LP   : constant Natural := Ada.Strings.Fixed.Index (Name, "(");
         RP   : constant Natural := Ada.Strings.Fixed.Index (Name, ")");
      begin
         if LP > 1 and RP = Name'Last and RP > LP + 1 then
            declare
               Base : constant String  := Name (Name'First .. LP - 1);
               Idx  : constant Integer :=
                 Integer'Value (Name (LP + 1 .. RP - 1));
               Key  : constant Ada.Strings.Unbounded.Unbounded_String :=
                 Ada.Strings.Unbounded.To_Unbounded_String (Base);
               Cur  : Base_Maps.Cursor := Bases.Find (Key);
            begin
               if Idx > 0 then
                  if not Base_Maps.Has_Element (Cur) then
                     Bases.Insert (Key, (Min_Idx => Idx, Max_Idx => Idx));
                  else
                     declare
                        R : Base_Range := Bases (Cur);
                     begin
                        R.Min_Idx := Natural'Min (R.Min_Idx, Idx);
                        R.Max_Idx := Natural'Max (R.Max_Idx, Idx);
                        Bases.Replace_Element (Cur, R);
                     end;
                  end if;
               end if;
            exception
               when Constraint_Error => null; -- non-integer subscript, skip
            end;
         end if;
      end;
   end loop;

   --  Pass 2: register each discovered base as a DIM array.
   for C in Bases.Iterate loop
      Dim_Array
        (Name      => Ada.Strings.Unbounded.To_String (Base_Maps.Key (C)),
         Start_Idx => Bases (C).Min_Idx,
         End_Idx   => Bases (C).Max_Idx,
         Is_Temp   => False);
   end loop;
end Register_Subscripted_Columns;
```

Adjust `Dim_Array`, `Column_Count`, `Column_Name` to match the exact subprogram names
present in `SData_Core.Table` and `SData_Core.Variables`.

- [ ] **Step 4: Call it in Execute_USE**

At the end of `SData_Core.Commands.Execute_USE`, after the file is loaded into the table:

```ada
SData_Core.Variables.Register_Subscripted_Columns;
```

- [ ] **Step 5: Build and run test**

```bash
cd ~/Develop/sdata-core && alr build
cd ~/Develop/sdata && alr build && make check 2>&1 | grep auto_array
```

Expected: `auto_array_detect` test passes.

- [ ] **Step 6: Run full test suite**

```bash
cd ~/Develop/sdata && make check
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
cd ~/Develop/sdata-core && git add -A
git commit -m "feat: add Register_Subscripted_Columns; call from Execute_USE"
cd ~/Develop/sdata && git add -A
git commit -m "test: add auto_array_detect integration test"
```

---

## Phase B — SData Refactor

---

### Task 9: Wire sdata Interpreter to Use SData_Core.Commands

Replace the inline command execution bodies for USE, SAVE, FPATH, OUTPUT, SELECT (filter),
KEEP, DROP, ARRAY, DIM, and RUN in `sdata-interpreter.adb` and
`sdata-interpreter-execute_declarative.adb` with calls to `SData_Core.Commands.*`.
The logic moved to sdata-core in Task 7; these become single-line dispatch calls.

**Files:**
- Modify: `~/Develop/sdata/src/sdata-interpreter.adb`
- Modify: `~/Develop/sdata/src/sdata-interpreter-execute_declarative.adb`

- [ ] **Step 1: Add with-clause to interpreter**

In `sdata-interpreter.adb`, add:

```ada
with SData_Core.Commands;
```

- [ ] **Step 2: Replace Stmt_USE handler**

Locate the `Stmt_USE` case branch in `sdata-interpreter-execute_declarative.adb` or
`sdata-interpreter.adb`. Replace the body with:

```ada
when Stmt_USE =>
   SData_Core.Commands.Execute_USE
     (S.Use_Path_Name (1 .. S.Use_Path_Len));
```

Verify there are no remaining local variables in the old handler that are referenced
elsewhere; remove them if so.

- [ ] **Step 3: Replace remaining shared handlers**

Apply the same delegation pattern for `Stmt_SAVE`, `Stmt_FPATH`, `Stmt_OUTPUT`,
`Stmt_SELECT_FILTER`, `Stmt_KEEP`, `Stmt_DROP`, `Stmt_ARRAY`, `Stmt_DIM`, and `Stmt_RUN`.
For each: locate the case branch, replace the body with a call to the corresponding
`SData_Core.Commands.Execute_*` procedure, passing the values extracted from the statement
record fields.

- [ ] **Step 4: Remove Select_Filter_Expr from interpreter body**

The variable `Select_Filter_Expr` at line 167 of `sdata-interpreter.adb` is now managed
by `SData_Core.Config.Runtime`. Remove the local declaration and the `Free_Expression` call
in the finalizer. Any reference to `Select_Filter_Expr` in `Rebuild_Filter_Map` now reads
`SData_Core.Config.Runtime.Select_Filter_Expr`.

- [ ] **Step 5: Build and test**

```bash
cd ~/Develop/sdata && alr build && make check
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
cd ~/Develop/sdata && git add -A
git commit -m "refactor: delegate shared command execution to SData_Core.Commands"
```

---

### Task 10: Remove VANDALIZE from SData

**Files to modify:**
- `src/lexer/sdata-lexer.ads` — remove `Token_VANDALIZE`
- `src/lexer/sdata-lexer.adb` — remove keyword mapping
- `src/ast/sdata-ast.ads` — remove `Stmt_VANDALIZE` and its record variant
- `src/parser/sdata-parser.adb` — remove VANDALIZE parser case
- `src/sdata-interpreter.adb` — remove from `Is_Immediate`, remove dispatch case
- `src/sdata-interpreter-execute_declarative.adb` — remove lines 301–661
- `src/sdata-help.adb` — remove `Help_VANDALIZE` procedure and its call
- `man/man1/sdata.1` — remove VANDALIZE section
- `doc/adrs.md` — update ADR-038 status to Superseded

- [ ] **Step 1: Remove Token_VANDALIZE from lexer**

In `src/lexer/sdata-lexer.ads`, remove `Token_VANDALIZE` from the `Token_Kind` enumeration.
In `src/lexer/sdata-lexer.adb`, remove the `"VANDALIZE" => Token_VANDALIZE` keyword entry.

- [ ] **Step 2: Remove Stmt_VANDALIZE from AST**

In `src/ast/sdata-ast.ads`, remove `Stmt_VANDALIZE` from `Statement_Kind` and remove the
`when Stmt_VANDALIZE =>` variant from the `Statement` record.

- [ ] **Step 3: Remove parser case**

In `src/parser/sdata-parser.adb`, remove the `when Token_VANDALIZE =>` case branch.

- [ ] **Step 4: Remove interpreter references**

In `src/sdata-interpreter.adb`:
- Remove `Stmt_VANDALIZE` from the `Is_Immediate` function (line ~89).
- Remove `Stmt_VANDALIZE` from the dispatch case (line ~613).

In `src/sdata-interpreter-execute_declarative.adb`:
- Delete lines 301–661 (the `when Stmt_VANDALIZE =>` block through end of file or next case).

- [ ] **Step 5: Remove help entry**

In `src/sdata-help.adb`, remove the `Help_VANDALIZE` procedure body and the call to it
in the `HELP` dispatch table.

- [ ] **Step 6: Remove man page section**

In `man/man1/sdata.1`, locate and remove the VANDALIZE entry (lines ~329–366).

- [ ] **Step 7: Move integration tests to holding directory**

```bash
mkdir -p ~/Develop/sdata-core/vandalize-tests
mv ~/Develop/sdata/tests/vandalize_*.cmd ~/Develop/sdata-core/vandalize-tests/
mv ~/Develop/sdata/tests/expected/vandalize_*.txt \
   ~/Develop/sdata-core/vandalize-tests/expected/ 2>/dev/null || true
```

These will be picked up by data-vandal in Task 16.

- [ ] **Step 8: Update ADR-038**

In `doc/adrs.md`, find ADR-038 (VANDALIZE design) and update:

```markdown
**Status:** Superseded — VANDALIZE moved to the standalone `data-vandal` application.
See `~/Develop/data-vandal` and the design spec at
`doc/specs/2026-05-19-data-vandal-design.md`.
```

- [ ] **Step 9: Build and run non-VANDALIZE test suite**

```bash
cd ~/Develop/sdata && alr build && make check
```

Expected: 118 integration tests pass (all non-VANDALIZE tests). If the test runner
counts tests, verify the number dropped by exactly 13.

- [ ] **Step 10: Commit**

```bash
cd ~/Develop/sdata && git add -A
git commit -m "feat: remove VANDALIZE; redirect to data-vandal (see ADR-038)"
```

---

## Phase C — data-vandal Application

---

### Task 11: Bootstrap data-vandal Project

**Files:**
- Create: `~/Develop/data-vandal/alire.toml`
- Create: `~/Develop/data-vandal/data_vandal.gpr`
- Create: `~/Develop/data-vandal/src/data_vandal_main.adb`
- Create: `~/Develop/data-vandal/src/data_vandal.ads`

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p ~/Develop/data-vandal/src/lexer \
         ~/Develop/data-vandal/src/ast \
         ~/Develop/data-vandal/src/parser \
         ~/Develop/data-vandal/tests/expected \
         ~/Develop/data-vandal/man/man1
```

- [ ] **Step 2: Write `alire.toml`**

```toml
name = "data_vandal"
description = "Standalone data vandalization interpreter"
version = "0.1.0"

authors = ["John L. Ries"]
maintainers = ["John L. Ries <john@theyarnbard.com>"]
licenses = "GPL-3.0-only"
executables = ["data-vandal"]

[[depends-on]]
sdata_core = "*"

[[pins]]
sdata_core = { path = "../sdata-core" }
```

- [ ] **Step 3: Write `data_vandal.gpr`**

```ada
with "sdata_core";

project Data_Vandal is
   for Languages use ("Ada");
   for Source_Dirs use ("src/**");
   for Object_Dir use "obj";
   for Exec_Dir use "bin";
   for Main use ("data_vandal_main.adb");

   package Compiler is
      for Default_Switches ("Ada") use
         ("-gnat2012", "-gnatwa", "-gnatwl", "-gnatwu", "-g", "-O2");
   end Compiler;

   package Builder is
      for Default_Switches ("Ada") use ("-g");
      for Executable ("data_vandal_main.adb") use "data-vandal";
   end Builder;
end Data_Vandal;
```

- [ ] **Step 4: Write root package and stub main**

`src/data_vandal.ads`:

```ada
--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
package Data_Vandal is
end Data_Vandal;
```

`src/data_vandal_main.adb`:

```ada
--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
with Ada.Text_IO; use Ada.Text_IO;
procedure Data_Vandal_Main is
begin
   Put_Line ("data-vandal 0.1.0 (stub)");
end Data_Vandal_Main;
```

- [ ] **Step 5: Build stub**

```bash
cd ~/Develop/data-vandal && alr build
bin/data-vandal
```

Expected output: `data-vandal 0.1.0 (stub)`

- [ ] **Step 6: Initialize git repo and commit**

```bash
cd ~/Develop/data-vandal && git init && git add -A
git commit -m "feat: bootstrap data-vandal project skeleton"
```

---

### Task 12: Implement Lexer and AST

**Files:**
- Create: `src/lexer/data_vandal-lexer.ads`
- Create: `src/lexer/data_vandal-lexer.adb`
- Create: `src/ast/data_vandal-ast.ads`
- Create: `src/ast/data_vandal-ast.adb`

- [ ] **Step 1: Write failing smoke test**

Create `tests/lex_smoke.cmd`:

```
USE tests/data/tiny.csv
QUIT
```

Create `tests/data/tiny.csv`:

```
a,b
1,2
```

This test will be used to verify end-to-end parsing in Task 14. Confirm it doesn't run yet.

- [ ] **Step 2: Write `src/lexer/data_vandal-lexer.ads`**

```ada
--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
package Data_Vandal.Lexer is

   type Token_Kind is (
      Token_USE, Token_FPATH, Token_OUTPUT, Token_SELECT,
      Token_KEEP, Token_DROP, Token_ARRAY,
      Token_VANDALIZE, Token_RUN, Token_HELP, Token_QUIT,
      --  VANDALIZE option keywords
      Token_INTO, Token_MISS, Token_SHUFFLE, Token_PERTURB, Token_BY,
      --  Literals and names
      Token_Identifier, Token_String_Literal,
      Token_Integer_Literal, Token_Float_Literal,
      --  Punctuation
      Token_Slash, Token_Equals, Token_Comma, Token_Dot,
      Token_LParen, Token_RParen,
      Token_EOL, Token_EOF, Token_Unknown);

   Max_Token_Text : constant := 256;

   type Token_Info is record
      Kind     : Token_Kind := Token_EOF;
      Text     : String (1 .. Max_Token_Text) := (others => ' ');
      Text_Len : Natural := 0;
      Line     : Positive := 1;
   end record;

   procedure Open_Script  (Path : String);
   procedure Open_String  (Source : String);
   procedure Close;

   procedure Next_Token   (T : out Token_Info);
   procedure Peek_Token   (T : out Token_Info);
   procedure Push_Back    (T : Token_Info);

   Lexer_Error : exception;

end Data_Vandal.Lexer;
```

- [ ] **Step 3: Write `src/lexer/data_vandal-lexer.adb`**

Model the implementation on `~/Develop/sdata/src/lexer/sdata-lexer.adb`, keeping only the
token kinds declared above. The keyword table maps:

| String | Token_Kind |
|---|---|
| `"USE"` | `Token_USE` |
| `"FPATH"` | `Token_FPATH` |
| `"OUTPUT"` | `Token_OUTPUT` |
| `"SELECT"` | `Token_SELECT` |
| `"KEEP"` | `Token_KEEP` |
| `"DROP"` | `Token_DROP` |
| `"ARRAY"` | `Token_ARRAY` |
| `"VANDALIZE"` | `Token_VANDALIZE` |
| `"RUN"` | `Token_RUN` |
| `"HELP"` | `Token_HELP` |
| `"QUIT"` / `"EXIT"` | `Token_QUIT` |
| `"INTO"` | `Token_INTO` |
| `"MISS"` | `Token_MISS` |
| `"SHUFFLE"` | `Token_SHUFFLE` |
| `"PERTURB"` | `Token_PERTURB` |
| `"BY"` | `Token_BY` |

All other alphanumeric sequences → `Token_Identifier`.
`/` → `Token_Slash` (used to introduce VANDALIZE options).
Quoted strings → `Token_String_Literal`.

- [ ] **Step 4: Write `src/ast/data_vandal-ast.ads`**

```ada
--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
with SData_Core.Evaluator;
with SData_Core.Config;

package Data_Vandal.AST is

   Max_Name_Len  : constant := 256;
   Max_Vars      : constant := 128;

   type Name_Array is array (1 .. Max_Vars) of String (1 .. Max_Name_Len);
   type Len_Array  is array (1 .. Max_Vars) of Natural;

   type Statement_Kind is (
      Stmt_USE, Stmt_FPATH, Stmt_OUTPUT, Stmt_SELECT_FILTER,
      Stmt_KEEP, Stmt_DROP, Stmt_ARRAY,
      Stmt_VANDALIZE, Stmt_RUN, Stmt_HELP, Stmt_QUIT);

   type Statement (Kind : Statement_Kind) is record
      case Kind is
         when Stmt_USE =>
            Use_Path     : String (1 .. Max_Name_Len);
            Use_Path_Len : Natural;

         when Stmt_FPATH =>
            FPath_Use        : String (1 .. Max_Name_Len);
            FPath_Use_Len    : Natural;
            FPath_Save       : String (1 .. Max_Name_Len);
            FPath_Save_Len   : Natural;
            FPath_Output     : String (1 .. Max_Name_Len);
            FPath_Output_Len : Natural;

         when Stmt_OUTPUT =>
            Out_Path     : String (1 .. Max_Name_Len);
            Out_Path_Len : Natural;
            Out_Fmt      : SData_Core.Config.Format_Type;

         when Stmt_SELECT_FILTER =>
            Condition : SData_Core.Evaluator.Expression_Access;

         when Stmt_KEEP | Stmt_DROP =>
            Var_Names : Name_Array;
            Var_Lens  : Len_Array;
            Var_Count : Natural;

         when Stmt_ARRAY =>
            Arr_Group : String (1 .. Max_Name_Len);
            Arr_Group_Len : Natural;
            Arr_Vars  : Name_Array;
            Arr_Lens  : Len_Array;
            Arr_Count : Natural;

         when Stmt_VANDALIZE =>
            Vand_Source      : String (1 .. Max_Name_Len);
            Vand_Source_Len  : Natural;
            Vand_Dest        : String (1 .. Max_Name_Len);
            Vand_Dest_Len    : Natural;
            Vand_Miss        : Boolean;
            Vand_Shuffle     : Boolean;
            Vand_Perturb     : Boolean;
            Vand_Mprob       : Float;
            Vand_Sprob       : Float;
            Vand_Pprob       : Float;
            Vand_SD_Frac     : Float;
            Vand_By_Vars     : Name_Array;
            Vand_By_Lens     : Len_Array;
            Vand_By_Count    : Natural;

         when Stmt_RUN | Stmt_QUIT | Stmt_HELP =>
            Help_Topic     : String (1 .. Max_Name_Len);
            Help_Topic_Len : Natural;
      end case;
   end record;

   type Statement_Access is access Statement;
   procedure Free (S : in out Statement_Access);

end Data_Vandal.AST;
```

- [ ] **Step 5: Write `src/ast/data_vandal-ast.adb`** (just `Free`)

```ada
with Ada.Unchecked_Deallocation;
package body Data_Vandal.AST is
   procedure Free_Stmt is new Ada.Unchecked_Deallocation (Statement, Statement_Access);
   procedure Free (S : in out Statement_Access) is
   begin
      if S /= null and then S.Kind = Stmt_SELECT_FILTER then
         SData_Core.Evaluator.Free_Expression (S.Condition);
      end if;
      Free_Stmt (S);
   end Free;
end Data_Vandal.AST;
```

- [ ] **Step 6: Build**

```bash
cd ~/Develop/data-vandal && alr build
```

Expected: compiles cleanly (no main yet uses the lexer/AST).

- [ ] **Step 7: Commit**

```bash
cd ~/Develop/data-vandal && git add -A
git commit -m "feat: add lexer and AST for data-vandal command subset"
```

---

### Task 13: Implement Parser

**Files:**
- Create: `src/parser/data_vandal-parser.ads`
- Create: `src/parser/data_vandal-parser.adb`

The parser is a simple top-down recursive descent over `Data_Vandal.Lexer` tokens, producing
`Data_Vandal.AST.Statement_Access` values one at a time. Model the structure on
`~/Develop/sdata/src/parser/sdata-parser.adb`, keeping only the grammar rules for the
supported commands.

- [ ] **Step 1: Write `src/parser/data_vandal-parser.ads`**

```ada
--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
with Data_Vandal.AST;

package Data_Vandal.Parser is

   --  Returns the next parsed statement, or null at EOF.
   --  Raises Parser_Error with a line-number message on syntax error.
   function Next_Statement return Data_Vandal.AST.Statement_Access;

   Parser_Error : exception;

end Data_Vandal.Parser;
```

- [ ] **Step 2: Write `src/parser/data_vandal-parser.adb`**

Key parsing rules (model each on the corresponding case in `sdata-parser.adb`):

**USE:** `USE <path>`  
```ada
when Token_USE =>
   Next_Token (T);   -- consume path
   S := new Statement (Stmt_USE);
   S.Use_Path (1 .. T.Text_Len) := T.Text (1 .. T.Text_Len);
   S.Use_Path_Len := T.Text_Len;
   return S;
```

**FPATH:** `FPATH [USE=<p>] [SAVE=<p>] [OUTPUT=<p>]`  
Parse keyword=value pairs; assign to the appropriate FPATH fields.

**OUTPUT:** `OUTPUT <path> [/<fmt>]`  
Parse path; optional `/CSV`, `/ODS`, `/XLSX` suffix sets `Out_Fmt`.

**SELECT:** Collect all tokens on the remainder of the line into a string, then:
```ada
S := new Statement (Stmt_SELECT_FILTER);
S.Condition := SData_Core.Evaluator.Parse_Expression (Collected_Text);
return S;
```

**KEEP / DROP:** `KEEP <var> [<var>...]` — read identifiers until EOL.

**ARRAY:** `ARRAY <group> <var> [<var>...]`

**VANDALIZE:** Model exactly on the VANDALIZE parser case from
`~/Develop/sdata/src/parser/sdata-parser.adb` (lines ~1356–1501). Copy and adapt,
replacing `SData.` references with `Data_Vandal.` for AST types and keeping the
option-parsing logic (INTO, /MISS, /SHUFFLE, /PERTURB, /BY) verbatim.

**RUN / QUIT / HELP:** Consume the keyword; parse optional topic for HELP.

Unknown token at statement start → raise `Parser_Error` with the token text and line number.

- [ ] **Step 3: Build**

```bash
cd ~/Develop/data-vandal && alr build
```

- [ ] **Step 4: Commit**

```bash
cd ~/Develop/data-vandal && git add -A
git commit -m "feat: add parser for data-vandal command subset"
```

---

### Task 14: Implement Interpreter (Stub VANDALIZE)

**Files:**
- Create: `src/data_vandal-interpreter.ads`
- Create: `src/data_vandal-interpreter.adb`
- Modify: `src/data_vandal_main.adb`

- [ ] **Step 1: Write first integration test**

Copy `tests/vandalize_stub.cmd` from `~/Develop/sdata-core/vandalize-tests/` (placed there in
Task 10 Step 7):

```bash
cp ~/Develop/sdata-core/vandalize-tests/vandalize_stub.cmd \
   ~/Develop/data-vandal/tests/
cp ~/Develop/sdata-core/vandalize-tests/expected/vandalize_stub.txt \
   ~/Develop/data-vandal/tests/expected/  2>/dev/null || true
```

Run it (will fail — interpreter not implemented yet):

```bash
cd ~/Develop/data-vandal && alr build && \
  bin/data-vandal tests/vandalize_stub.cmd
```

Expected: "stub" output or crash.

- [ ] **Step 2: Write `src/data_vandal-interpreter.ads`**

```ada
--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
package Data_Vandal.Interpreter is
   procedure Run_Script (Path : String);
   procedure Run_Interactive;
   Interpreter_Error : exception;
end Data_Vandal.Interpreter;
```

- [ ] **Step 3: Write `src/data_vandal-interpreter.adb`**

```ada
with Data_Vandal.Lexer;
with Data_Vandal.AST;    use Data_Vandal.AST;
with Data_Vandal.Parser; use Data_Vandal.Parser;
with SData_Core.Commands;
with SData_Core.Config;
with Ada.Text_IO; use Ada.Text_IO;

package body Data_Vandal.Interpreter is

   procedure Dispatch (S : Statement_Access) is
   begin
      case S.Kind is
         when Stmt_USE =>
            SData_Core.Commands.Execute_USE
              (S.Use_Path (1 .. S.Use_Path_Len));

         when Stmt_FPATH =>
            SData_Core.Commands.Execute_FPATH
              (S.FPath_Use  (1 .. S.FPath_Use_Len),
               S.FPath_Save (1 .. S.FPath_Save_Len),
               S.FPath_Output (1 .. S.FPath_Output_Len),
               "");

         when Stmt_OUTPUT =>
            SData_Core.Commands.Execute_OUTPUT
              (S.Out_Path (1 .. S.Out_Path_Len), S.Out_Fmt);

         when Stmt_SELECT_FILTER =>
            SData_Core.Commands.Execute_SELECT (S.Condition);

         when Stmt_KEEP =>
            SData_Core.Commands.Execute_KEEP
              (S.Var_Names, S.Var_Lens, S.Var_Count);

         when Stmt_DROP =>
            SData_Core.Commands.Execute_DROP
              (S.Var_Names, S.Var_Lens, S.Var_Count);

         when Stmt_ARRAY =>
            SData_Core.Commands.Execute_ARRAY
              (S.Arr_Group (1 .. S.Arr_Group_Len),
               S.Arr_Vars, S.Arr_Lens, S.Arr_Count);

         when Stmt_VANDALIZE =>
            raise Interpreter_Error with "VANDALIZE not yet implemented";

         when Stmt_RUN =>
            SData_Core.Commands.Execute_RUN;

         when Stmt_QUIT =>
            raise Program_Error;  -- handled by caller loop

         when Stmt_HELP =>
            Put_Line ("HELP not yet implemented");
      end case;
   end Dispatch;

   procedure Run_Loop is
      S : Statement_Access;
   begin
      loop
         S := Next_Statement;
         exit when S = null;
         if S.Kind = Stmt_QUIT then
            Free (S);
            exit;
         end if;
         Dispatch (S);
         Free (S);
      end loop;
   exception
      when Parser_Error | Interpreter_Error =>
         raise;
   end Run_Loop;

   procedure Run_Script (Path : String) is
   begin
      Data_Vandal.Lexer.Open_Script (Path);
      Run_Loop;
      Data_Vandal.Lexer.Close;
   end Run_Script;

   procedure Run_Interactive is
   begin
      Data_Vandal.Lexer.Open_String ("");
      Run_Loop;
      Data_Vandal.Lexer.Close;
   end Run_Interactive;

end Data_Vandal.Interpreter;
```

- [ ] **Step 4: Update main**

```ada
with Data_Vandal.Interpreter;
with Ada.Command_Line; use Ada.Command_Line;
with Ada.Text_IO;      use Ada.Text_IO;

procedure Data_Vandal_Main is
begin
   if Argument_Count = 0 then
      Data_Vandal.Interpreter.Run_Interactive;
   else
      for I in 1 .. Argument_Count loop
         Data_Vandal.Interpreter.Run_Script (Argument (I));
      end loop;
   end if;
exception
   when Data_Vandal.Interpreter.Interpreter_Error =>
      Put_Line (Standard_Error, "Error: " & Exception_Message);
      Set_Exit_Status (Failure);
   when Data_Vandal.Parser.Parser_Error =>
      Put_Line (Standard_Error, "Syntax error: " & Exception_Message);
      Set_Exit_Status (Failure);
end Data_Vandal_Main;
```

- [ ] **Step 5: Build and run stub test**

```bash
cd ~/Develop/data-vandal && alr build
bin/data-vandal tests/vandalize_stub.cmd
```

Expected: fails at the VANDALIZE dispatch ("VANDALIZE not yet implemented") — confirms
parsing and common-command dispatch work up to that point.

- [ ] **Step 6: Commit**

```bash
cd ~/Develop/data-vandal && git add -A
git commit -m "feat: add interpreter dispatch loop; stub VANDALIZE"
```

---

### Task 15: Port VANDALIZE Executor

**Files:**
- Create: `src/data_vandal-execute_vandalize.ads`
- Create: `src/data_vandal-execute_vandalize.adb`
- Modify: `src/data_vandal-interpreter.adb`

- [ ] **Step 1: Write `src/data_vandal-execute_vandalize.ads`**

```ada
--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
with Data_Vandal.AST;

package Data_Vandal.Execute_VANDALIZE is
   procedure Execute (S : Data_Vandal.AST.Statement_Access);
end Data_Vandal.Execute_VANDALIZE;
```

- [ ] **Step 2: Write `src/data_vandal-execute_vandalize.adb`**

Copy lines 301–661 from
`~/Develop/sdata/src/sdata-interpreter-execute_declarative.adb` (the
`when Stmt_VANDALIZE =>` block). Wrap them in the new package body:

```ada
with SData_Core.Table;     use SData_Core.Table;
with SData_Core.Values;    use SData_Core.Values;
with SData_Core.Variables; use SData_Core.Variables;
with SData_Core.Statistics;

package body Data_Vandal.Execute_VANDALIZE is
   procedure Execute (S : Data_Vandal.AST.Statement_Access) is
      --  All locals from the original Stmt_VANDALIZE block go here.
      --  ... (ported verbatim) ...
   begin
      --  Body ported verbatim from sdata-interpreter-execute_declarative.adb
      --  lines 301-661, with these mechanical substitutions:
      --    S.Vand_*       field names remain the same (AST field names match)
      --    SData.Table    → SData_Core.Table
      --    SData.Values   → SData_Core.Values
      --    SData.Variables → SData_Core.Variables
      --    SData.Statistics → SData_Core.Statistics
      null; -- remove this once the body is pasted
   end Execute;
end Data_Vandal.Execute_VANDALIZE;
```

Apply the package-rename substitutions throughout the body. No algorithmic changes.

- [ ] **Step 3: Wire into interpreter**

In `src/data_vandal-interpreter.adb`, replace the stub:

```ada
when Stmt_VANDALIZE =>
   raise Interpreter_Error with "VANDALIZE not yet implemented";
```

with:

```ada
when Stmt_VANDALIZE =>
   Data_Vandal.Execute_VANDALIZE.Execute (S);
```

Add `with Data_Vandal.Execute_VANDALIZE;` at the top.

- [ ] **Step 4: Build**

```bash
cd ~/Develop/data-vandal && alr build
```

Fix any compilation errors from the port (typically wrong field names or missing
`with` clauses).

- [ ] **Step 5: Commit**

```bash
cd ~/Develop/data-vandal && git add -A
git commit -m "feat: port VANDALIZE executor from sdata"
```

---

### Task 16: Port Integration Tests and Build Test Infrastructure

**Files:**
- Create: `~/Develop/data-vandal/Makefile`
- Create: `tests/*.cmd` (ported from sdata-core/vandalize-tests/)
- Create: `tests/expected/*.txt`

- [ ] **Step 1: Copy test files**

```bash
cp ~/Develop/sdata-core/vandalize-tests/*.cmd \
   ~/Develop/data-vandal/tests/
cp ~/Develop/sdata-core/vandalize-tests/expected/*.txt \
   ~/Develop/data-vandal/tests/expected/ 2>/dev/null || true
```

- [ ] **Step 2: Write `Makefile`**

Model on `~/Develop/sdata/Makefile`'s integration test runner. Key targets:

```makefile
BINARY  := bin/data-vandal
TESTDIR := tests
EXPDIR  := tests/expected

build:
	alr build

check: build
	@pass=0; fail=0; \
	for cmd in $(TESTDIR)/*.cmd; do \
	  base=$$(basename $$cmd .cmd); \
	  actual=$$($(BINARY) $$cmd 2>&1); \
	  expected=$$(cat $(EXPDIR)/$$base.txt 2>/dev/null); \
	  if [ "$$actual" = "$$expected" ]; then \
	    pass=$$((pass+1)); \
	  else \
	    echo "FAIL: $$base"; \
	    diff <(echo "$$expected") <(echo "$$actual"); \
	    fail=$$((fail+1)); \
	  end; \
	done; \
	echo "$$pass passed, $$fail failed"

.PHONY: build check
```

Adapt the runner to exactly match the mechanism used in `~/Develop/sdata/Makefile`.

- [ ] **Step 3: Run tests**

```bash
cd ~/Develop/data-vandal && make check
```

Fix any failures by comparing the actual output of `bin/data-vandal` against the expected
files. Common causes: path differences, missing SAVE output, different error message wording.
Update expected files where the difference is cosmetic (e.g., binary name in error messages).

- [ ] **Step 4: Verify all 13 tests pass**

```bash
cd ~/Develop/data-vandal && make check 2>&1 | tail -3
```

Expected: `13 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
cd ~/Develop/data-vandal && git add -A
git commit -m "test: port all 13 vandalize integration tests; all pass"
```

---

### Task 17: Help System, Man Page, and Final Verification

**Files:**
- Create: `src/data_vandal-help.ads`
- Create: `src/data_vandal-help.adb`
- Create: `man/man1/data-vandal.1`
- Modify: `src/data_vandal-interpreter.adb` — wire up HELP dispatch

- [ ] **Step 1: Write `src/data_vandal-help.ads`**

```ada
package Data_Vandal.Help is
   procedure Show (Topic : String);
end Data_Vandal.Help;
```

- [ ] **Step 2: Write `src/data_vandal-help.adb`**

Model on `~/Develop/sdata/src/sdata-help.adb`. Include entries for:
`USE`, `FPATH`, `OUTPUT`, `SELECT`, `KEEP`, `DROP`, `ARRAY`, `VANDALIZE`, `RUN`,
`HELP`, `QUIT`. The `VANDALIZE` entry text is copied verbatim from `sdata-help.adb`'s
`Help_VANDALIZE` procedure. Unknown topic → list all available topics.

- [ ] **Step 3: Wire HELP into interpreter**

In `src/data_vandal-interpreter.adb`, replace:

```ada
when Stmt_HELP =>
   Put_Line ("HELP not yet implemented");
```

with:

```ada
when Stmt_HELP =>
   Data_Vandal.Help.Show (S.Help_Topic (1 .. S.Help_Topic_Len));
```

Add `with Data_Vandal.Help;` at the top.

- [ ] **Step 4: Write man page**

Create `man/man1/data-vandal.1`. Model the structure on `~/Develop/sdata/man/man1/sdata.1`,
retaining only the sections relevant to the supported command set. Key sections:

```groff
.TH DATA-VANDAL 1 "2026-05-19" "data-vandal 0.1.0"
.SH NAME
data-vandal \- controlled data vandalization interpreter
.SH SYNOPSIS
.B data-vandal
[\fIscript.cmd\fR ...]
.SH DESCRIPTION
...
.SH COMMANDS
.SS USE
...
.SS VANDALIZE
(copy from sdata.1 verbatim)
...
.SH SEE ALSO
.BR sdata (1)
```

- [ ] **Step 5: Final build and full test run**

```bash
cd ~/Develop/data-vandal && alr build && make check
```

Expected: 13 tests pass.

```bash
cd ~/Develop/sdata && make check
```

Expected: 118 tests pass.

- [ ] **Step 6: Final commit**

```bash
cd ~/Develop/data-vandal && git add -A
git commit -m "feat: add help system and man page; data-vandal complete"

cd ~/Develop/sdata && git add -A
git commit -m "docs: final cleanup after data-vandal extraction"
```

---

## Self-Review Checklist

- **Spec §1 (Overview / VANDALIZE removal from SData):** Covered by Tasks 10 and 15.
- **Spec §2 (Repo layout):** Task 1 (sdata-core), Task 11 (data-vandal), path pin in Task 2.
- **Spec §3.1 (Package moves):** Tasks 2–5 cover all 21 packages listed.
- **Spec §3.2 (Commands, Interpreter_State):** Task 7. Note: `Interpreter_State` is
  implemented as package-level state in `SData_Core.Config.Runtime` (where it already lives)
  rather than a separate record, which is simpler and consistent with the existing architecture.
  `Select_Filter_Expr` is added to `Config.Runtime` in Task 7 Step 1.
- **Spec §3.3 (Register_Subscripted_Columns):** Task 8.
- **Spec §4 (data-vandal structure):** Tasks 11–17.
- **Spec §4.2 (VANDALIZE executor port):** Task 15.
- **Spec §4.3 (ARRAY without DIM):** AST in Task 12 omits `Stmt_DIM`; auto-detection
  inherited from sdata-core via `Execute_USE`.
- **Spec §5.1 (Removed artifacts):** Task 10 covers all listed items.
- **Spec §5.4 (118 regression tests):** Verified in Tasks 9 and 10.
- **Spec §6 (Command set):** All commands present in lexer (Task 12), AST (Task 12),
  parser (Task 13), and interpreter dispatch (Task 14). SELECT expression language
  via `Parse_Expression` (Task 6). KEEP and DROP via `SData_Core.Commands` (Task 7).
- **Spec §7 (Dependencies):** `sdata-core/alire.toml` in Task 1 carries all four deps.
  `data-vandal/alire.toml` in Task 11 depends only on sdata-core.
