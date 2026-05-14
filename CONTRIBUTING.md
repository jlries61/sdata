# Contributing to SData

SData is written in Ada 2012 and built with [Alire](https://alire.ada.dev/),
Ada's package manager. This guide gets you from zero to a working development
environment in about 15 minutes, even if you have never used Ada before.

---

## Quickstart

### 1. Install Alire

Alire manages the Ada toolchain and all library dependencies automatically.
Download and run the installer from [alire.ada.dev](https://alire.ada.dev/):

```sh
curl -sSfL https://alire.ada.dev/get-alire | sh
```

Then add `~/.local/bin` to your PATH (or follow the installer's instructions).
Verify:

```sh
alr --version
```

Alire downloads its own GNAT toolchain on first use — you do not need a
system-installed GCC/Ada package.

### 2. Install the system dependency

SData uses SQLite for disk-backed storage of large datasets. Install the
development headers for your distribution:

| Distribution | Command |
|---|---|
| Debian / Ubuntu | `sudo apt install libsqlite3-dev` |
| Fedora / RHEL / Rocky | `sudo dnf install sqlite-devel` |
| openSUSE | `sudo zypper install sqlite3-devel` |

### 3. Clone the repository

```sh
git clone https://github.com/jlries61/sdata.git
cd sdata
```

### 4. Build

```sh
alr build
```

The first run downloads the GNAT toolchain and Ada library dependencies
(Zip-Ada, XML-Ada, MathPaqs, ada_sqlite3). This takes 1–2 minutes; subsequent
builds are fast.

### 5. Run the test suite

```sh
alr exec -- make check
```

This runs five unit test binaries followed by 131 integration tests. Expected
output ends with:

```
All 131 tests passed.
```

### 6. Verify the binary

```sh
bin/sdata --version
```

### 7. Try it interactively

```sh
bin/sdata
```

Type `PRINT 1 + 1` at the prompt, then `QUIT`. You should see `2`.

---

## macOS

The build works on macOS with Alire. Two known issues:

- **SDK headers**: if `alr build` fails with `_stdio.h: No such file or
  directory`, set `SDKROOT` and `C_INCLUDE_PATH` before building. See the
  **macOS** section of `README.md` for the exact commands.
- **`timeout` command**: the test harness needs GNU `timeout`, which macOS
  does not ship. Install via MacPorts (`sudo port install coreutils`); the
  Makefile detects `gtimeout` automatically.

## Windows

The recommended path is Alire inside an MSYS2 MinGW64 shell. See the
**Windows** section of `README.md` for full instructions.

---

## Code Map

| Package / file | Purpose |
|---|---|
| `sdata_main.adb` | Entry point — argument parsing, mode dispatch |
| `sdata-interpreter.adb` + subunits | Statement executor and data step engine |
| `src/parser/sdata-parser.adb` | Token stream → AST |
| `src/lexer/sdata-lexer.ads` | Characters → tokens |
| `sdata-evaluator.adb` + child packages | AST expression → Value |
| `sdata-variables.adb` | PDV, temporary and permanent symbols, hold semantics |
| `sdata-table.adb` | In-memory column store with SQLite spill |
| `sdata-file_io.adb`, `-csv`, `-odf`, `-ooxml`, `-helpers` | CSV, ODF, and OOXML read/write |
| `sdata-statistics.adb` | Statistical distribution functions |
| `sdata-help.adb` | HELP command dispatcher |
| `sdata-system.adb` | SYSTEM/SHELL command execution and timeout |
| `sdata-values.adb` | Core `Value` variant type (Numeric/Integer/String/Missing) |

The interpreter subunits (`sdata-interpreter-execute_*.adb`, etc.) each handle
one category of statement. Adding a new command means touching the parser, one
interpreter subunit, and the help system — the architecture doc explains which.

For the full pipeline diagram and three-tier execution model, read
`doc/architecture.md`.

---

## Development Workflow

### Edit → build → test

```sh
alr build && alr exec -- make check
```

The build step recompiles only changed units. The full test suite runs in under
30 seconds.

### Running a single integration test

Each `.cmd` file in `tests/` is a self-contained SData script. Run one
directly:

```sh
bin/sdata tests/aggregates.cmd
```

Compare against its expected output:

```sh
diff tests/expected/aggregates.out <(bin/sdata tests/aggregates.cmd 2>&1)
```

Or use the Makefile target:

```sh
make run FILE=tests/aggregates.cmd
```

### Running a single unit test binary

When you change one subsystem, run only the relevant test binary:

```sh
bin/evaluator_unit_test
bin/interpreter_unit_test
bin/file_io_unit_test
bin/sdata_unit_test       # Variables / PDV layer
bin/csv_unit_test         # CSV tokenizer
```

### Debugging

`--debug` emits a trace of every statement executed and every variable
assignment to stderr:

```sh
bin/sdata --debug tests/aggregates.cmd
```

---

## Key Reference Documents

| Document | What it covers |
|---|---|
| `doc/architecture.md` | System overview, package map, three-tier execution model, trust model |
| `doc/adrs.md` | All architectural decisions (ADR-001–037) with rationale |
| `man/man1/sdata.1` | Complete language reference — statements, expressions, built-in functions |
| `doc/SOFTWARE_STANDARDS_REVIEW.md` | Living quality audit; findings marked resolved with commit hashes |
| `doc/threat_model.md` | STRIDE threat model: trust model, attack surface, mitigations, known gaps |
| `CLAUDE.md` | AI agent context, also useful for humans: build commands, key architecture notes, source layout |

The authoritative language specification is `doc/design.odt` (LibreOffice).
Convert it to plain text for terminal reading:

```sh
soffice --headless --convert-to txt doc/design.odt
# writes design.txt
```

---

## Fuzzing

Two AFL++-ready fuzz drivers live in `tests/`:

| Driver | Surface covered |
|---|---|
| `bin/csv_fuzz_driver` | All six `SData.CSV` public functions (tokenizer, unquoting, type detection) |
| `bin/parser_fuzz_driver` | Lexer + recursive-descent parser — parse only, interpreter never invoked |

### Corpus regression (no AFL++ required)

The seed corpus in `tests/fuzz_corpus/` is checked in CI. Run it locally:

```sh
alr exec -- make fuzz-corpus
```

This runs every seed file through both drivers and fails if any causes an
unexpected crash. Add new seed files to `tests/fuzz_corpus/csv/` or
`tests/fuzz_corpus/script/` whenever you find an interesting input.

### Running AFL++ (full coverage-guided fuzzing)

Install AFL++:

```sh
# Debian / Ubuntu
sudo apt install afl++
# Fedora / RHEL / Rocky
sudo dnf install aflplusplus
```

Build the drivers with AFL++ instrumentation and run:

```sh
# Set the AFL++ compiler wrapper before building
export CC=afl-clang-fast
export CXX=afl-clang-fast++
alr build

# Fuzz the CSV tokenizer
mkdir -p fuzz_out/csv
afl-fuzz -i tests/fuzz_corpus/csv -o fuzz_out/csv -- bin/csv_fuzz_driver

# Fuzz the parser (separate terminal)
mkdir -p fuzz_out/script
afl-fuzz -i tests/fuzz_corpus/script -o fuzz_out/script -- bin/parser_fuzz_driver
```

Any crash found by AFL++ lands in `fuzz_out/*/crashes/`. Reproduce it with:

```sh
bin/csv_fuzz_driver < fuzz_out/csv/crashes/id:000000,...
```

When a crash is confirmed, add the minimised input to the corpus and open a
bug report. Use `afl-tmin` to reduce the crashing input to its smallest form
before committing it.

---

## Branching and Commit Conventions

Work on a feature branch. Keep commits focused; use conventional prefixes:

| Prefix | Use for |
|---|---|
| `feat:` | New language feature or command |
| `fix:` | Bug fix |
| `refactor:` | Internal restructuring with no behaviour change |
| `test:` | Test additions or corrections |
| `doc:` | Documentation only |

The test suite must pass before pushing:

```sh
alr exec -- make check
```

Do not use `--no-verify` to bypass hooks.
