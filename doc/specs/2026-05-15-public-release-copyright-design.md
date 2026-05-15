# Public Release — Copyright and License Notices

**Date:** 2026-05-15
**Status:** Approved
**Author:** John L. Ries

## Summary

Prepare SData for public release by adding the GPL v3 license file to all
binary package formats, adding copyright/license headers to every source file,
adding a copyright one-liner to the interactive session banner, and adding a
`--copyright` CLI flag that prints the full short notice.

A secondary fix is correcting `debian/copyright`, which incorrectly declares
MIT as the upstream license; the authoritative license is GPL v3 (the `LICENSE`
file at the project root).

---

## 1. Copyright Constant (`sdata-config.ads`)

Two new string constants are added immediately after `Version_Str`:

```ada
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
```

- `Copyright_Str` — used in the banner (single line).
- `Copyright_Notice` — printed verbatim by `--copyright`.

Both constants live in `sdata-config.ads` alongside `Version_Str` so that
copyright and version metadata share a single canonical location.

---

## 2. Banner and CLI Changes (`sdata_main.adb`)

### 2.1 Interactive banner

`Run_REPL` adds a copyright line between the version line and the
"Interactive Console" line:

```
SData Statistical Interpreter version 0.6.14
Copyright (C) 2026 John L. Ries <john@theyarnbard.com>. License GPLv3+. Run 'sdata --copyright' for details.
Interactive Console. Type QUIT to exit.
```

Implementation: `Ada.Text_IO.Put_Line (Copyright_Str & ". License GPLv3+. Run 'sdata --copyright' for details.")`.

### 2.2 `--copyright` flag

Added to the argument parsing loop before the filename fall-through:

```ada
elsif Arg = "--copyright" then
   Ada.Text_IO.Put_Line (SData.Config.Copyright_Notice);
   return;
```

Behaviour mirrors `--version` and `--help`: print and exit immediately with
success status.

### 2.3 `Print_Usage`

One new line added to the options list:

```
  --copyright          Show copyright and license information
```

### 2.4 Man page (`man/man1/sdata.1`)

A new `--copyright` entry is added to the OPTIONS section, immediately after
the `--version` entry, following the same groff formatting.

---

## 3. Source File Copyright Headers

### 3.1 Ada files

All `.ads` and `.adb` files under `src/` (including subdirectories `ast/`,
`lexer/`, `parser/`) and all test source files under `tests/` receive a
three-line copyright block prepended before any existing content:

```ada
--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>
```

The block is placed at the very top of each file (before `with` clauses and
before any existing doc comments), followed by a blank line to separate it
from the existing first line of content.

### 3.2 C file

`src/sdata_privilege.c` receives the equivalent notice in C block-comment style:

```c
/*
 * Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
 * License: GNU General Public License v3 or later
 * See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>
 */
```

### 3.3 Scope

| Directory | Files |
|---|---|
| `src/` (top-level) | 58 `.ads`/`.adb` files |
| `src/ast/` | 2 files |
| `src/lexer/` | 2 files |
| `src/parser/` | 2 files |
| `src/sdata_privilege.c` | 1 C file |
| `tests/` | 9 `.adb` files |
| **Total** | **74 files** |

---

## 4. Packaging Changes

### 4.1 Makefile `install` target

Add one line to install the license file into the doc directory:

```makefile
install -m 644 LICENSE $(DOC_DIR)/LICENSE
```

This automatically covers Slackware (which installs via `make install DESTDIR=...`).

### 4.2 macOS `pkg` target

Add `LICENSE` to the explicit file list in the `make pkg` inline script,
alongside `README.md`:

```sh
install -m 644 LICENSE "$$PKG_ROOT/usr/local/share/doc/sdata/LICENSE"; \
```

### 4.3 RPM spec (`sdata.spec`)

Add `%license LICENSE` to the `%files` section. The RPM `%license` macro
installs the file to `/usr/share/licenses/sdata/LICENSE`:

```spec
%license LICENSE
```

### 4.4 `debian/copyright`

Correct the license field for both `Files: *` and `Files: debian/*` stanzas
from `MIT` to `GPL-3.0-or-later`. The `dh` toolchain installs this file
automatically as `/usr/share/doc/sdata/copyright`.

### 4.5 Windows MSI (`wix/sdata.wxs`)

Already ships `LICENSE` as `LICENSE.txt`. No change required.

---

## 5. Out of Scope

- Adding a `COPYING` symlink (project uses `LICENSE`; both the source headers
  and `--copyright` output reference it by that name).
- Updating `bump-version.sh` for the copyright year — year changes are rare
  and can be handled manually when needed.
- Any change to the language-visible behaviour of the SData interpreter.
