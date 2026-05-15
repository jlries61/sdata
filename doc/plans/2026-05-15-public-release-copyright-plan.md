# Public Release Copyright/License Notices — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add GPL v3 copyright notices to all source files, the interactive banner, a new `--copyright` CLI flag, and all binary package formats.

**Architecture:** A single `Copyright_Str`/`Copyright_Notice` constant pair is added to `sdata-config.ads` (alongside the existing `Version_Str`) and referenced from `sdata_main.adb`. Source file headers are prepended mechanically via a shell loop. Packaging fixes touch the Makefile, RPM spec, and `debian/copyright`. The Windows MSI already ships the license; no change needed there.

**Tech Stack:** Ada 2012, GNAT/GPRbuild, Alire (`alr build`), Makefile, groff man page

---

## Files Modified

| File | Change |
|---|---|
| `src/sdata-config.ads` | Add `Copyright_Str` and `Copyright_Notice` constants |
| `src/sdata_main.adb` | Add `--copyright` flag, update banner, update `Print_Usage` |
| `man/man1/sdata.1` | Add `--copyright` entry to OPTIONS section |
| All 65 files in `src/` (`.ads`, `.adb`, `.c`) | Prepend 3-line copyright header |
| All 9 files in `tests/` (`.adb`) | Prepend 3-line copyright header |
| `Makefile` | Install `LICENSE` in `install` and `pkg` targets |
| `sdata.spec` | Add `%license LICENSE` to `%files` |
| `debian/copyright` | Correct `MIT` → `GPL-3.0-or-later` |

---

## Task 1: Add copyright constants to `sdata-config.ads`

**Files:**
- Modify: `src/sdata-config.ads`

- [ ] **Step 1: Add the two constants after `Version_Str`**

  In `src/sdata-config.ads`, replace the block ending at `end SData.Config;`:

  ```ada
     Version_Str   : constant String :=
        Natural'Image (Version_Major)(2 .. Natural'Image (Version_Major)'Last) & "." &
        Natural'Image (Version_Minor)(2 .. Natural'Image (Version_Minor)'Last) & "." &
        Natural'Image (Version_Patch)(2 .. Natural'Image (Version_Patch)'Last);

     --  Copyright and license information
     Copyright_Str : constant String :=
        "Copyright (C) 2026 John L. Ries <john@theyarnbard.com>";

     Copyright_Notice : constant String :=
        "SData version " & Version_Str & ASCII.LF &
        Copyright_Str & ASCII.LF & ASCII.LF &
        "This program is free software: you can redistribute it and/or modify" & ASCII.LF &
        "it under the terms of the GNU General Public License as published by" & ASCII.LF &
        "the Free Software Foundation, either version 3 of the License, or" & ASCII.LF &
        "(at your option) any later version." & ASCII.LF & ASCII.LF &
        "This program is distributed in the hope that it will be useful," & ASCII.LF &
        "but WITHOUT ANY WARRANTY; without even the implied warranty of" & ASCII.LF &
        "MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the" & ASCII.LF &
        "GNU General Public License for more details." & ASCII.LF & ASCII.LF &
        "You should have received a copy of the GNU General Public License" & ASCII.LF &
        "along with this program. If not, see <https://www.gnu.org/licenses/>.";

  end SData.Config;
  ```

- [ ] **Step 2: Build to verify compilation**

  ```bash
  alr build
  ```

  Expected: build succeeds with no errors.

- [ ] **Step 3: Commit**

  ```bash
  git add src/sdata-config.ads
  git commit -m "feat: add Copyright_Str and Copyright_Notice constants to SData.Config"
  ```

---

## Task 2: Update interactive banner (`sdata_main.adb`)

**Files:**
- Modify: `src/sdata_main.adb` (lines 101–103 in `Run_REPL`)

- [ ] **Step 1: Insert copyright line between the version line and the "Interactive Console" line**

  Locate in `Run_REPL`:

  ```ada
        Ada.Text_IO.Put_Line ("SData Statistical Interpreter version "
                              & SData.Config.Version_Str);
        Ada.Text_IO.Put_Line ("Interactive Console. Type QUIT to exit.");
  ```

  Replace with:

  ```ada
        Ada.Text_IO.Put_Line ("SData Statistical Interpreter version "
                              & SData.Config.Version_Str);
        Ada.Text_IO.Put_Line (SData.Config.Copyright_Str
                              & ". License GPLv3+. Run 'sdata --copyright' for details.");
        Ada.Text_IO.Put_Line ("Interactive Console. Type QUIT to exit.");
  ```

- [ ] **Step 2: Build**

  ```bash
  alr build
  ```

  Expected: build succeeds with no errors.

- [ ] **Step 3: Verify banner output**

  ```bash
  printf "" | bin/sdata
  ```

  Expected output (first 3 lines):

  ```
  SData Statistical Interpreter version 0.6.14
  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>. License GPLv3+. Run 'sdata --copyright' for details.
  Interactive Console. Type QUIT to exit.
  ```

- [ ] **Step 4: Commit**

  ```bash
  git add src/sdata_main.adb
  git commit -m "feat: add copyright notice to interactive session banner"
  ```

---

## Task 3: Add `--copyright` CLI flag (`sdata_main.adb`)

**Files:**
- Modify: `src/sdata_main.adb`

- [ ] **Step 1: Add the `--copyright` branch to the argument parsing loop**

  Locate in the `while Idx <= Argument_Count loop` block:

  ```ada
           if Arg = "-h" or Arg = "--help" then
              Print_Usage;
              return;
           elsif Arg = "-v" or Arg = "--version" then
              Put_Line ("SData version " & Version_Str);
              return;
  ```

  Add the new branch immediately after the `--version` block:

  ```ada
           elsif Arg = "--copyright" then
              Ada.Text_IO.Put_Line (SData.Config.Copyright_Notice);
              return;
  ```

- [ ] **Step 2: Add `--copyright` to `Print_Usage`**

  Locate in `Print_Usage`:

  ```ada
        Put_Line ("  -h, --help    Show this help message");
        Put_Line ("  -v, --version Show version information");
  ```

  Add the new line immediately after:

  ```ada
        Put_Line ("  --copyright   Show copyright and license information");
  ```

- [ ] **Step 3: Build**

  ```bash
  alr build
  ```

  Expected: build succeeds with no errors.

- [ ] **Step 4: Verify `--copyright` output**

  ```bash
  bin/sdata --copyright
  ```

  Expected output:

  ```
  SData version 0.6.14
  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program. If not, see <https://www.gnu.org/licenses/>.
  ```

- [ ] **Step 5: Verify `--help` lists `--copyright`**

  ```bash
  bin/sdata --help | grep copyright
  ```

  Expected: `  --copyright   Show copyright and license information`

- [ ] **Step 6: Verify exit status is success**

  ```bash
  bin/sdata --copyright > /dev/null; echo "exit: $?"
  ```

  Expected: `exit: 0`

- [ ] **Step 7: Commit**

  ```bash
  git add src/sdata_main.adb
  git commit -m "feat: add --copyright flag printing GPL v3 short notice"
  ```

---

## Task 4: Update man page (`man/man1/sdata.1`)

**Files:**
- Modify: `man/man1/sdata.1`

- [ ] **Step 1: Add `--copyright` entry immediately after the `--version` entry**

  Locate (around line 28):

  ```groff
  .TP
  .BR \-v ", " \-\-version
  Print the version string and exit.
  .TP
  ```

  Replace with:

  ```groff
  .TP
  .BR \-v ", " \-\-version
  Print the version string and exit.
  .TP
  .B \-\-copyright
  Print copyright and license information and exit.
  .TP
  ```

- [ ] **Step 2: Verify the man page renders correctly**

  ```bash
  man man/man1/sdata.1 | grep -A 2 "copyright"
  ```

  Expected: the `--copyright` entry appears in the OPTIONS section.

- [ ] **Step 3: Commit**

  ```bash
  git add man/man1/sdata.1
  git commit -m "doc: add --copyright entry to man page OPTIONS section"
  ```

---

## Task 5: Add copyright headers to Ada source files

**Files:**
- Modify: all 65 `.ads`/`.adb` files under `src/` and 9 `.adb` files under `tests/`

- [ ] **Step 1: Prepend the header to all Ada files**

  Run from the project root:

  ```bash
  ADA_HEADER='--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
  --  License: GNU General Public License v3 or later
  --  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>
  '
  find src tests -name '*.ads' -o -name '*.adb' | while IFS= read -r f; do
    tmp=$(mktemp)
    printf '%s\n%s' "$ADA_HEADER" "$(cat "$f")" > "$tmp"
    mv "$tmp" "$f"
  done
  ```

  This prepends 3 header lines + 1 blank separator line before the existing content of every Ada file.

- [ ] **Step 2: Verify all 74 Ada files have the header**

  ```bash
  find src tests -name '*.ads' -o -name '*.adb' | xargs grep -l "Copyright (C) 2026" | wc -l
  ```

  Expected: `74`

- [ ] **Step 3: Build to verify the headers don't break compilation**

  ```bash
  alr build
  ```

  Expected: build succeeds with no errors.

- [ ] **Step 4: Run full test suite**

  ```bash
  make check
  ```

  Expected: all 131 integration tests pass, unit tests pass.

- [ ] **Step 5: Commit**

  ```bash
  git add src/ tests/
  git commit -m "chore: add GPL v3 copyright headers to all Ada source files"
  ```

---

## Task 6: Add copyright header to C source file

**Files:**
- Modify: `src/sdata_privilege.c`

- [ ] **Step 1: Prepend the C-style header**

  ```bash
  C_HEADER='/*
   * Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
   * License: GNU General Public License v3 or later
   * See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>
   */
  '
  tmp=$(mktemp)
  printf '%s\n%s' "$C_HEADER" "$(cat src/sdata_privilege.c)" > "$tmp"
  mv "$tmp" src/sdata_privilege.c
  ```

- [ ] **Step 2: Verify the header**

  ```bash
  head -6 src/sdata_privilege.c
  ```

  Expected:

  ```c
  /*
   * Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
   * License: GNU General Public License v3 or later
   * See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>
   */
  ```

- [ ] **Step 3: Build to verify C compilation is unaffected**

  ```bash
  alr build
  ```

  Expected: build succeeds with no errors.

- [ ] **Step 4: Commit**

  ```bash
  git add src/sdata_privilege.c
  git commit -m "chore: add GPL v3 copyright header to sdata_privilege.c"
  ```

---

## Task 7: Install LICENSE in Makefile targets

**Files:**
- Modify: `Makefile`

- [ ] **Step 1: Add LICENSE to the `install` target**

  Locate in the `install` target:

  ```makefile
  	install -m 644 README.md $(DOC_DIR)/README.md
  	install -m 644 doc/threat_model.md $(DOC_DIR)/threat_model.md
  ```

  Add one line after:

  ```makefile
  	install -m 644 LICENSE $(DOC_DIR)/LICENSE
  ```

- [ ] **Step 2: Add LICENSE to the macOS `pkg` target**

  Locate in the `pkg` target inline script:

  ```makefile
  	 install -m 644 README.md "$$PKG_ROOT/usr/local/share/doc/sdata/README.md"; \
  	 install -m 644 doc/threat_model.md "$$PKG_ROOT/usr/local/share/doc/sdata/threat_model.md"; \
  ```

  Add one line after:

  ```makefile
  	 install -m 644 LICENSE "$$PKG_ROOT/usr/local/share/doc/sdata/LICENSE"; \
  ```

- [ ] **Step 3: Verify the install target places LICENSE correctly**

  ```bash
  DESTDIR=$(mktemp -d)
  make install DESTDIR="$DESTDIR" PREFIX=/usr
  ls "$DESTDIR/usr/share/doc/sdata/"
  ```

  Expected output includes `LICENSE`.

  Clean up: `rm -rf "$DESTDIR"`

- [ ] **Step 4: Commit**

  ```bash
  git add Makefile
  git commit -m "chore: install LICENSE file in all binary package formats"
  ```

---

## Task 8: Add `%license` to RPM spec (`sdata.spec`)

**Files:**
- Modify: `sdata.spec`

- [ ] **Step 1: Add `%license LICENSE` to the `%files` section**

  Locate in `sdata.spec`:

  ```spec
  %files
  %{_bindir}/sdata
  ```

  Insert immediately after `%files`:

  ```spec
  %files
  %license LICENSE
  %{_bindir}/sdata
  ```

- [ ] **Step 2: Verify the change**

  ```bash
  grep -A 5 "^%files" sdata.spec
  ```

  Expected:

  ```
  %files
  %license LICENSE
  %{_bindir}/sdata
  ...
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add sdata.spec
  git commit -m "chore: add %license LICENSE to RPM spec %files section"
  ```

---

## Task 9: Fix `debian/copyright` license declaration

**Files:**
- Modify: `debian/copyright`

- [ ] **Step 1: Correct the license for `Files: *` and `Files: debian/*`**

  The current content incorrectly declares MIT. Change both `License: MIT` lines that apply to project files:

  ```
  Files: *
  Copyright: 2026 John L. Ries <john@theyarnbard.com>
  License: GPL-3.0-or-later

  Files: zipada_*
  Copyright: Gautier de Montmollin
  License: MIT

  Files: xmlada_*
  Copyright: AdaCore
  License: GPL-3.0+

  Files: mathpaqs_*
  Copyright: Gautier de Montmollin
  License: MIT

  Files: debian/*
  Copyright: 2026 John L. Ries <john@theyarnbard.com>
  License: GPL-3.0-or-later
  ```

  The third-party stanzas (`zipada_*`, `xmlada_*`, `mathpaqs_*`) are unchanged.

- [ ] **Step 2: Verify the file**

  ```bash
  grep "License:" debian/copyright
  ```

  Expected:

  ```
  License: GPL-3.0-or-later
  License: MIT
  License: GPL-3.0+
  License: MIT
  License: GPL-3.0-or-later
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add debian/copyright
  git commit -m "fix: correct debian/copyright license from MIT to GPL-3.0-or-later"
  ```

---

## Task 10: Final verification

- [ ] **Step 1: Full test suite**

  ```bash
  make check
  ```

  Expected: all 131 integration tests pass, all unit tests pass. No regressions.

- [ ] **Step 2: Verify `--copyright` output**

  ```bash
  bin/sdata --copyright | grep -c "GNU General Public License"
  ```

  Expected: `3` (appears in the preamble, "version 3" line, and closing sentence).

- [ ] **Step 3: Verify interactive banner**

  ```bash
  printf "" | bin/sdata | head -3
  ```

  Expected:

  ```
  SData Statistical Interpreter version 0.6.14
  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>. License GPLv3+. Run 'sdata --copyright' for details.
  Interactive Console. Type QUIT to exit.
  ```

- [ ] **Step 4: Verify all source files have a header**

  ```bash
  find src tests -name '*.ads' -o -name '*.adb' -o -name '*.c' | \
    xargs grep -L "Copyright (C) 2026"
  ```

  Expected: no output (every file has the header).

- [ ] **Step 5: Verify LICENSE is installed**

  ```bash
  DESTDIR=$(mktemp -d)
  make install DESTDIR="$DESTDIR" PREFIX=/usr
  ls "$DESTDIR/usr/share/doc/sdata/"
  rm -rf "$DESTDIR"
  ```

  Expected output includes: `LICENSE  README.md  threat_model.md`
