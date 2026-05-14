# SData — Statistical Data Interpreter

SData is a command interpreter for tabular data processing, inspired by Systat
BASIC's data step model. It operates on a two-dimensional table of rows and
columns, supporting floating point, integer, and character data types. Features
include:

- CSV, ODF, and OOXML spreadsheet I/O
- Comprehensive statistical distribution functions (normal, t, F, chi-square,
  etc.)
- Aggregate functions (mean, median, standard deviation, etc.)
- Permanent and temporary variables, arrays (permanent, temporary, and virtual)
- Control flow (IF/THEN/ELSE, FOR/NEXT, WHILE, REPEAT/UNTIL, SELECT/CASE)
- BY-group processing
- SYSTEM/SHELL integration (can be disabled)

## Build Requirements

SData is written in Ada 2012 and requires:

- **GNAT** — the GNU Ada compiler (part of GCC)
  - `gcc-ada` on openSUSE/SLES
  - `gcc-gnat` on Fedora/RHEL/Rocky/Alma/Mageia
  - `gnat` on Debian/Ubuntu
- **GPRbuild** — the GNAT project build tool
- **GNU Make**

### Ada Library Dependencies

SData depends on three Ada libraries:

| Library   | Version        | Purpose                    |
|-----------|----------------|----------------------------|
| Zip-Ada   | 61.0.0         | ZIP/ODF archive handling   |
| XML/Ada   | 26.0.0         | XML parsing (ODF/OOXML)    |
| MathPaqs  | 20260205.0.0   | Numerical/random functions |

If you use [Alire](https://alire.ada.dev/), dependencies are resolved
automatically. Otherwise, obtain the library source tarballs and place them in
a sibling directory so that the Makefile can auto-detect them, or set
`GPR_PROJECT_PATH` manually.

## Building

```sh
make
```

This invokes `gprbuild` and produces the `sdata` executable in `bin/`.

To run the test suite:

```sh
make check
```

To install (default prefix `/usr/local`):

```sh
make install
```

Or specify a custom prefix:

```sh
make install PREFIX=/usr DESTDIR=/path/to/staging
```

## Packaging

### RPM (Fedora, openSUSE, RHEL, etc.)

Build a source RPM:

```sh
make srpm
```

This creates `sdata-0.6.14-1.src.rpm` which can be built with `rpmbuild
--rebuild` or submitted to a build service. The vendored library tarballs must
be present in `../Data/tarballs/`.

### Debian/Ubuntu

Build a Debian source package:

```sh
make dsc
```

This creates the `.dsc`, `.orig.tar.gz`, and `.debian.tar.xz` files. Build the
binary package with `dpkg-buildpackage` or `pbuilder`.

### Slackware

Create a SlackBuild tarball:

```sh
make slackware
```

This creates `sdata-0.6.14-slackbuild.tar.gz` containing the SlackBuild script,
source tarball, and vendored dependencies. Extract and run `./sdata.SlackBuild`
as root to build the package.

### macOS

#### Building with Alire

If you use Alire on macOS, the Alire-managed GNAT toolchain is a pre-built
binary targeting a specific macOS SDK version. If your macOS version is older
than the one the toolchain was compiled for, the C compiler will not find
Apple's private SDK headers (such as `_stdio.h`) when compiling the bundled
`sqlite3.c` in the `ada_sqlite3` dependency, producing an error like:

```
fatal error: _stdio.h: No such file or directory
```

The fix is to set `C_INCLUDE_PATH` so that GCC can locate the SDK headers:

```sh
export SDKROOT=$(xcrun --show-sdk-path)
export C_INCLUDE_PATH=$SDKROOT/usr/include
alr build
```

Add both lines to your `~/.zshrc` or `~/.zprofile` to make the setting
permanent. Note that `SDKROOT` alone is not sufficient — unlike Clang, the
GCC-based GNAT toolchain does not automatically apply it as `-isysroot`.

This issue is not specific to Alire: the same fix is needed whenever the
pre-built GNAT binary is used with `gprbuild` directly. A GNAT compiled
natively for your macOS version will have the correct SDK paths embedded and
should not require this workaround.

#### Running the Test Suite

The test harness uses the GNU coreutils `timeout` command, which is not
included with macOS. Install it via MacPorts (`sudo port install coreutils`),
after which it is available as `gtimeout`. The Makefile detects `gtimeout`
automatically, so no further configuration is needed.

#### Installer Package

Build a macOS installer package:

```sh
make pkg
```

This creates `sdata-0.6.14.pkg`. The `sdata` binary must already be built
(`make` first). Requires the `pkgbuild` tool (included with Xcode).

### Windows

#### Building

The recommended toolchain is [Alire](https://alire.ada.dev/) inside an MSYS2
MinGW64 shell. Install Alire from the MSYS2 package or from the upstream
release, then:

```sh
alr build
```

Or, equivalently:

```sh
alr exec -- make
```

The build produces `bin\sdata.exe`. Cygwin works too — Alire and a recent GNAT
toolchain on PATH are the only hard requirements.

#### MSI Installer

Build a Windows MSI installer:

```sh
alr exec -- make msi
```

This creates `sdata-0.6.14-x64.msi`, a per-machine x64 installer that places
`sdata.exe`, `LICENSE.txt`, `README.md`, and an HTML rendering of the man page
under `C:\Program Files\sdata\` and appends that directory to the system
`PATH`. Requirements:

- **WiX Toolset v4 or later** (v7 recommended) via the .NET tool:
  ```sh
  dotnet tool install --global wix
  ```
  Verify with `wix --version`. WiX requires the .NET 8 (or later) SDK.

- **pandoc** — converts the man page to HTML for inclusion in the installer.
  In MSYS2: `pacman -S mingw-w64-x86_64-pandoc`. Alternately, Pandoc can be
  installed via [Chocolatey](https://chocolatey.org/) or downloaded directly
  from the [Pandoc website](https://pandoc.org/installing.html).

Install the resulting MSI with `msiexec /i sdata-0.6.14-x64.msi`, or by
double-clicking it. After install, `sdata` is available from any new CMD or
PowerShell window.

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
scripts/bump-version.sh 0.6.14 "Add spreadsheet formula evaluation and multi-sheet support."
```

The script validates the `N.N.N` version format, detects the current version
from `src/sdata-config.ads`, and warns if any old version strings remain after
the update (expected in changelog history).

## Quick Start

### Interactive Mode

Run `sdata` with no arguments to enter the interactive console:

```
$ sdata
SData Statistical Interpreter version 0.6.14
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
