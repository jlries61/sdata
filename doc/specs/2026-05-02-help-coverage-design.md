# HELP Command Test Coverage Design

## Goal

Add 8 behavioral tests for the `HELP` command dispatcher in `sdata-help.adb`.
The dispatcher has four code paths; none are currently covered by automated
tests. No source code changes — tests only.

## Architecture

The existing `make check` harness picks up every `tests/*.cmd` file
automatically and diffs its output against `tests/expected/<base>.out`. Adding
tests requires only:

1. A `.cmd` file in `tests/`
2. A corresponding `.out` file in `tests/expected/`

No Makefile changes. No new executables. Expected output is captured by running
`./bin/sdata tests/<file>.cmd` once and saving stdout.

## Dispatcher Code Paths

`Print_Help` in `sdata-help.adb` has exactly four branches:

| Branch | Trigger | What happens |
|---|---|---|
| Index | `HELP` (no topic) | `Help_Index` — prints command/function index |
| Full reference | `HELP /ALL` | Two loops over `Help_Table`: commands then functions |
| Specific topic | `HELP <known>` | Calls `E.Handler.all` for the matching entry |
| Unknown topic | `HELP <unknown>` | Prints "Help topic not found: X" error |

Within the "specific topic" branch, three sub-cases exist in the table:
multi-line command handler, single-line function handler, and alias (two keys
sharing one handler).

## Test Files

| `.cmd` file | Topic | Branch / sub-case |
|---|---|---|
| `help_index.cmd` | _(bare `HELP`)_ | Index branch |
| `help_all.cmd` | `HELP /ALL` | Full-reference branch |
| `help_use.cmd` | `HELP USE` | Specific topic — multi-line command |
| `help_abs.cmd` | `HELP ABS` | Specific topic — single-line function |
| `help_distributions.cmd` | `HELP DISTRIBUTIONS` | Specific topic — long narrative handler |
| `help_unknown.cmd` | `HELP BOGUS` | Unknown topic — error message |
| `help_lowercase.cmd` | `HELP use` | Case-insensitive lookup (same output as `HELP USE`) |
| `help_alias.cmd` | `HELP DIST` | Alias → shares handler with `HELP DISTRIBUTIONS` |

Each `.cmd` file contains exactly one statement: the `HELP` invocation.
No `QUIT` or `NEW` needed — the interpreter reads to EOF.

### Example `.cmd` content

```
HELP USE
```

### Expected output capture

```bash
./bin/sdata tests/help_use.cmd > tests/expected/help_use.out
```

Repeated for each of the 8 files. Captured output becomes the regression
baseline — any future change to the help text that isn't reflected in the
expected file will fail the test.

## What This Guards

- Dispatch logic: bare topic, `/ALL`, known topic, unknown topic
- Case normalisation: `To_Upper` applied before lookup
- Alias resolution: two keys routing to the same handler
- The full `/ALL` dump: verifies both loops execute without error and that
  every `In_Cmd` and `In_Func` entry is reachable

## What This Does Not Guard

- Content of every individual handler (100+ topics). Individual handler text
  is tested only for the 6 non-`/ALL` specific-topic cases chosen above.
  The `/ALL` test provides a safety net for any handler that crashes at
  runtime, even if its exact text is not individually diffed.
- Interactive REPL invocation of `HELP` — covered implicitly since the
  interpreter delegates to the same `Print_Help` entry point.

## Success Criteria

1. `make check` passes all 99 existing tests unchanged.
2. 8 new tests pass (107 total).
3. Deliberately breaking one key in `Help_Table` causes the corresponding
   test to fail.
