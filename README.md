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

This creates `sdata-0.3.4-1.src.rpm` which can be built with `rpmbuild
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

This creates `sdata-0.3.4-slackbuild.tar.gz` containing the SlackBuild script,
source tarball, and vendored dependencies. Extract and run `./sdata.SlackBuild`
as root to build the package.

### macOS

Build a macOS installer package:

```sh
make pkg
```

This creates `sdata-0.3.4.pkg`. The `sdata` binary must already be built
(`make` first). Requires the `pkgbuild` tool (included with Xcode).

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
scripts/bump-version.sh 0.4.0 "Add spreadsheet formula evaluation and multi-sheet support."
```

The script validates the `N.N.N` version format, detects the current version
from `src/sdata-config.ads`, and warns if any old version strings remain after
the update (expected in changelog history).

## Quick Start

### Interactive Mode

Run `sdata` with no arguments to enter the interactive console:

```
$ sdata
SData Statistical Interpreter version 0.3.4
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
  --noshell                 Disable SHELL/SYSTEM commands
  -k, --continue-on-error   Continue after statement errors
  --ignore-math-errors      Math errors return missing instead of halting
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
