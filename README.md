# SData — Statistical Data Interpreter

SData is a command interpreter for tabular data processing, inspired by Systat
BASIC's data step model. It operates on a two-dimensional table of rows and
columns, supporting floating point, integer, and character data types. Features
include:

- CSV, ODF, and OOXML spreadsheet I/O
- Column types from the header-name suffix on load: `name$` → string,
  `name%` → integer, otherwise floating-point (non-numeric data → string)
- Comprehensive statistical distribution functions (normal, t, F, chi-square,
  etc.)
- Aggregate functions (mean, median, standard deviation, etc.)
- Permanent and temporary variables, arrays (permanent, temporary, and virtual)
- Control flow (IF/THEN/ELSE, FOR/NEXT, WHILE, REPEAT/UNTIL, SELECT/CASE)
- BY-group processing, including the `AGGREGATE` command (collapse to one summary row per group)
- SYSTEM/SHELL integration (can be disabled)

## Build Requirements

SData is written in Ada 2012 and requires:

- **GNAT** — the GNU Ada compiler (part of GCC)
  - `gcc-ada` on openSUSE/SLES
  - `gcc-gnat` on Fedora/RHEL/Rocky/Alma/Mageia
  - `gnat` on Debian/Ubuntu
- **GPRbuild** — the GNAT project build tool
- **GNU Make**

### Runtime Requirements

Enforcing a timeout on `SYSTEM`/`SHELL` commands requires a `timeout(1)`
utility on `PATH` — GNU coreutils `timeout`, or its `gtimeout` alias on
platforms where the bare name is taken by a different tool (SData prefers
`gtimeout` and is silent and identical across platforms when it is present).
A timeout is in effect whenever `OPTIONS SHELLTIMEOUT` is greater than zero;
**batch scripts apply a default of 300 seconds**, so in practice any script
that runs external commands needs this utility. If a timeout is requested but
no such utility is found, SData reports a clear error rather than running the
command unbounded.

The dependency does **not** apply when `OPTIONS SHELLTIMEOUT 0` is set
(unlimited — the interactive default) or to the bare interactive `SYSTEM`
shell. macOS ships no `timeout`; install GNU coreutils via MacPorts
(`sudo port install coreutils`) or Homebrew (`brew install coreutils`).

### Ada Library Dependencies

SData depends on a sibling Alire library crate, `sdata-core`, that holds the
data layer, evaluator, and command-execution machinery shared with the
[data-vandal](#related-projects) application. `sdata-core` in turn depends on
four Ada libraries:

| Library      | Version        | Purpose                              |
|--------------|----------------|--------------------------------------|
| sdata-core   | ^0.1.0         | Shared data layer and evaluator      |
| Zip-Ada      | 61.0.0         | ZIP/ODF archive handling             |
| XML/Ada      | 26.0.0         | XML parsing (ODF/OOXML)              |
| MathPaqs     | 20260205.0.0   | Numerical/random functions           |
| ada_sqlite3  | 0.1.1          | SQLite spillover for large tables    |

If you use [Alire](https://alire.ada.dev/), the four upstream libraries are
resolved automatically, but `sdata-core` is currently consumed via a local path
pin: clone it as a sibling directory next to `sdata`:

```
~/Develop/
├── sdata/
└── sdata-core/
```

Without Alire, obtain the library source tarballs and place them in a sibling
directory so that the Makefile can auto-detect them, or set `GPR_PROJECT_PATH`
manually; `sdata-core` similarly needs to be on `GPR_PROJECT_PATH`.

### Related Projects

- **sdata-core** — the shared Alire library crate (data layer, evaluator,
  command execution) consumed by both sdata and data-vandal. Versioned and
  released independently of sdata. See [ADR-039](doc/adrs.md) and the design
  spec at `doc/specs/2026-05-19-data-vandal-design.md`.
- **data-vandal** — a standalone interpreter for controlled data degradation
  (the former `VANDALIZE` command, extracted into its own application in
  v0.11.0). See [ADR-038](doc/adrs.md) (now superseded) and the data-vandal
  repository for the application's own README.

## Installation

### From source with Alire (recommended)

```sh
git clone https://github.com/jlries61/sdata.git
git clone https://github.com/jlries61/sdata-core.git   # path-pinned sibling
cd sdata
alr build
```

The binary lands at `bin/sdata`.  Run `make install` (with optional
`PREFIX=` and `DESTDIR=`) to drop it into `/usr/local/bin/` along with
the man page and `LICENSE`:

```sh
make install                                  # default PREFIX=/usr/local
make install PREFIX=/usr DESTDIR=/path/to/stage
```

To run the test suite:

```sh
make check
```

### From source without Alire

The Makefile falls back to invoking `gprbuild` directly if `alr` is not
on `PATH`.  Make sure the dependency `.gpr` files (Zip-Ada, XML/Ada,
MathPaqs, ada_sqlite3, sdata-core) are on `GPR_PROJECT_PATH`.

### Source RPM (Fedora, openSUSE, RHEL, …)

```sh
make srpm
rpmbuild --rebuild sdata-X.Y.Z-1.src.rpm
```

`make srpm` bundles vendored tarballs of the four Ada library
dependencies plus a fresh tarball of the sibling `sdata-core` repo, so
the downstream build environment needs only the system Ada compiler
(`gcc-ada` on openSUSE/SLES, `gcc-gnat` on Fedora/RHEL/Mageia), `make`,
and `sqlite-devel` — no Alire required.

### Debian source package (Debian, Ubuntu, …)

```sh
make dsc
dpkg-source -x sdata_X.Y.Z-1.dsc
cd sdata-X.Y.Z
dpkg-buildpackage -us -uc -b
```

`make dsc` produces the standard Debian source-package triple
(`sdata_X.Y.Z-1.dsc`, `sdata_X.Y.Z.orig.tar.gz`,
`sdata_X.Y.Z-1.debian.tar.xz`), bundling the same vendored
tarballs the RPM target uses.  Downstream builds need only `gnat`,
`gprbuild`, `make`, and `libsqlite3-dev` — no Alire required.

`make dsc` itself needs `dpkg-source` (from the `dpkg-dev` package)
on the machine that builds the source package; once the triple is
produced, the binary build can run on any Debian-derivative with the
Build-Depends above plus `debhelper-compat (= 13)` installed.

### Slackware package

```sh
make slackware
tar xzf sdata-X.Y.Z-slackbuild.tar.gz
./sdata.SlackBuild              # as root; emits a .txz in /tmp
installpkg /tmp/sdata-X.Y.Z-x86_64-1_SBo.txz
```

`make slackware` produces two artefacts in the repo root: the
self-contained `sdata-X.Y.Z-slackbuild.tar.gz` and the
upstream-source tarball `sdata-X.Y.Z.tar.gz`.  The slackbuild
tarball already contains a copy of the source tarball plus the four
vendored Ada library tarballs, the sdata-core snapshot,
`sdata.SlackBuild`, `sdata.info`, and `slack-desc` — so extracting it
gives the SlackBuild script everything it needs.

`sdata.SlackBuild` reads the upstream source tarball at
`$CWD/sdata-X.Y.Z.tar.gz`, so it must be present in the
directory you invoke the script from (whether that's where you
extracted the slackbuild tarball, or the repo root directly after
`make slackware`).

The SlackBuild script drives `gnatmake` directly rather than
`gprbuild`, so the downstream build environment needs only the
system Ada toolchain (`gcc-gnat`) and `sqlite3-devel`.

The `make slackware` step itself only needs the standard build tools
(`tar`, `gzip`, `git`) on the packager's machine.

### macOS

#### Building with Alire

The Alire-managed GNAT toolchain on macOS is a pre-built binary
targeting a specific macOS SDK version.  If your macOS version is
older than the one the toolchain was compiled for, the C compiler
will not find Apple's private SDK headers (such as `_stdio.h`) when
compiling the bundled `sqlite3.c` in the `ada_sqlite3` dependency,
producing an error like:

```
fatal error: _stdio.h: No such file or directory
```

The fix is to set `C_INCLUDE_PATH` so that GCC can locate the SDK
headers:

```sh
export SDKROOT=$(xcrun --show-sdk-path)
export C_INCLUDE_PATH=$SDKROOT/usr/include
alr build
```

Add both lines to your `~/.zshrc` or `~/.zprofile` to make the
setting permanent.  Note that `SDKROOT` alone is not sufficient —
unlike Clang, the GCC-based GNAT toolchain does not automatically
apply it as `-isysroot`.

This issue is not specific to Alire: the same fix is needed
whenever the pre-built GNAT binary is used with `gprbuild` directly.
A GNAT compiled natively for your macOS version will have the
correct SDK paths embedded and should not require this workaround.

#### Running the test suite

The harness uses the GNU coreutils `timeout` command, which is not
included with macOS.  Install it via MacPorts
(`sudo port install coreutils`) or Homebrew
(`brew install coreutils`); both ship it as `gtimeout`.  The
Makefile detects `gtimeout` automatically, so no further
configuration is needed.

#### Installer package

```sh
make pkg
sudo installer -pkg sdata-X.Y.Z.pkg -target /
```

`make pkg` produces `sdata-X.Y.Z.pkg` in the repo root: a per-machine
installer that places `sdata`, the gzipped man page, `README.md`,
and `LICENSE` under `/usr/local/{bin,share/...}` and registers itself
with the system installer database.  Requires the `pkgbuild` tool
(included with the Xcode command-line tools; `xcode-select --install`
if not already installed) and a built `bin/sdata` (the recipe depends
on the `build` target, so a fresh `alr build` runs automatically if
needed).

Install with `installer` as above, or by double-clicking the `.pkg`
in Finder.  Uninstall is a manual `sudo rm` of the four installed
files plus their per-app docdir.

### Windows

#### Building

The recommended toolchain is [Alire](https://alire.ada.dev/) inside
an MSYS2 MinGW64 shell.  Install Alire from the MSYS2 package or
from the upstream release, then:

```sh
alr build
```

Or, equivalently:

```sh
alr exec -- make
```

The build produces `bin\sdata.exe`.  Cygwin works too — Alire and a
recent GNAT toolchain on `PATH` are the only hard requirements.

#### MSI installer

```sh
alr exec -- make msi
```

This creates `sdata-X.Y.Z-x64.msi`, a per-machine x64 installer that
places `sdata.exe`, `LICENSE.txt`, `README.md`, and an HTML rendering
of the man page under `C:\Program Files\sdata\` and appends that
directory to the system `PATH`.  Requirements:

- **WiX Toolset v4 or later** (v7 recommended) via the .NET tool:
  ```sh
  dotnet tool install --global wix
  ```
  Verify with `wix --version`.  WiX requires the .NET 8 (or later)
  SDK.

- **pandoc** — converts the man page to HTML for inclusion in the
  installer.  In MSYS2: `pacman -S mingw-w64-x86_64-pandoc`.
  Alternately, pandoc can be installed via
  [Chocolatey](https://chocolatey.org/) or downloaded directly from
  the [pandoc website](https://pandoc.org/installing.html).

Install the resulting MSI with `msiexec /i sdata-X.Y.Z-x64.msi`,
or by double-clicking it.  After install, `sdata` is available
from any new CMD or PowerShell window.

## Release Management

The `scripts/bump-version.sh` script updates the version string in all nine
tracked locations atomically (source, Makefile, alire.toml, SlackBuild, man
page, README, RPM spec, and Debian changelog), then optionally builds, tests,
commits, and tags.

```sh
scripts/bump-version.sh <new-version> "<changelog-summary>"
```

For example:

```sh
scripts/bump-version.sh 0.11.0 "Fix path resolution in FPATH SUBMIT handler."
```

The script validates the `N.N.N` version format, detects the current version
from `src/sdata-version.ads`, and warns if any old version strings remain after
the update (expected in changelog history).

## Quick Start

### Interactive Mode

Run `sdata` with no arguments to enter the interactive console:

```
$ sdata
SData Statistical Interpreter version 0.11.0
Interactive Console. Type QUIT to exit.
sdata> use "mydata.csv"
sdata> print recno, name$, score
sdata> run
sdata> quit
```

### Batch Mode

Write commands in a file and pass it as an argument:

```sh
sdata myscript.cmd
```

### Command Line Options

```
sdata [options] [filename]

  -h, --help                Show help
  -v, --version             Show version
  -m <size>                 Max in-memory table size
  -t <count>                Max temporary variables
  --clen <len>              Max character variable length
  --noshell                 Disable SHELL/SYSTEM commands; also disables -p
  -k, --continue-on-error   Continue after statement errors
  --ignore-math-errors      Math errors return missing instead of halting
  -p <pager>                External pager command for interactive output (ignored in batch mode)
  -o <file>                 Console output file
  -q                        Quiet mode (suppress console output)
```

### Getting Help

From the interactive console or in a script:

```
HELP              — List all commands and functions
HELP <command>    — Detailed help for a specific command or function
HELP /ALL         — Full reference for all commands and functions
```

## License

GPL-3.0. See [LICENSE](LICENSE) for the full text.

## Author

John L. Ries <john@theyarnbard.com>
