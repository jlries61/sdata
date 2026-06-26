# INSERT command — design spec

**Issue:** [#32 — INSERT command desired](https://github.com/jlries61/sdata/issues/32)
**Date:** 2026-06-26
**Status:** Approved (pending implementation plan)

## Problem

In interactive mode, deferred statements (LET, SET, PRINT, IF, …) can only be
**appended** to the program buffer. A user can `DELETE n[-m]` to remove buffer
entries and `LIST` to view them, but there is no way to add a new statement
anywhere other than the end. Replacing an erroneous statement with a correct one,
or otherwise editing a resident program, is therefore needlessly awkward.

## Solution overview

Add an immediate `INSERT` command that positions an **insertion cursor** in the
program buffer. While the cursor is set, newly-typed deferred statements are
inserted at the cursor (advancing it past each one) instead of being appended.

This is purely a REPL / program-buffer feature local to the `sdata` crate. It does
**not** touch `sdata-core` (no data-layer, evaluator, or shared-command changes).

## Syntax

```
INSERT [ n | $ ]
```

| Form         | Effect                                                        |
|--------------|--------------------------------------------------------------|
| `INSERT 0`   | Cursor **before line 1** (beginning of program).             |
| `INSERT n`   | Cursor **after existing line n** (1-based).                  |
| `INSERT $`   | Cursor at **end** — normal append. This is the default.      |
| `INSERT`     | Bare form; identical to `INSERT $`.                           |

`n` is a whole number. `INSERT n` where `n` exceeds the current buffer length
**warns and clamps to end** (append mode), e.g.:

```
Warning: INSERT line 9 out of range (buffer has 4 entries); inserting at end.
```

A **negative** line number (e.g. `INSERT -3`) is **rejected**: it warns and leaves
the cursor unchanged (no-op). Line numbers are uniformly positive 1-based across
`LIST` / `DELETE` / `INSERT`; `$` already covers "the end", so Python-style
count-from-end indexing is intentionally not supported (YAGNI). The parser must
consume the leading `-` and any following number so it does not dangle as a stray
token:

```
Warning: INSERT line number must be >= 0; insertion point unchanged.
```

## Cursor model (sticky)

Two new pieces of interpreter state:

- `Append_Mode : Boolean := True` — when true, statements append (today's
  behavior).
- `Insert_Point : Natural` — meaningful only when `Append_Mode` is false; the
  number of lines the cursor sits *after* (0 = before line 1).

Behavior:

1. `INSERT $` / bare `INSERT` → `Append_Mode := True`.
2. `INSERT 0` → `Append_Mode := False; Insert_Point := 0`.
3. `INSERT n` (`1 <= n <= length`) → `Append_Mode := False; Insert_Point := n`.
4. `INSERT n` (`n > length`) → warn; `Append_Mode := True` (clamp to end).
5. `INSERT -n` (negative, parser-flagged invalid) → warn; cursor unchanged (no-op).

When a deferred statement is queued and `Append_Mode` is false, it is inserted
**after** `Insert_Point` (vector index `Insert_Point + 1`) and the cursor advances:
`Insert_Point := Insert_Point + 1`. Consecutive statements therefore insert in the
order typed, immediately after one another. (Once `Insert_Point` reaches `length`,
further inserts are equivalent to appends, but `Append_Mode` is not flipped — the
distinction only matters for `LIST` display and is harmless.)

### Lifetime

The cursor is **sticky**: it persists across `RUN` (running the program does not
move it). It is reset to append-mode (`Append_Mode := True`) only by:

- `NEW` (which clears the buffer), via the existing `Clear_Active_Program`, and
- another `INSERT` command.

### Interaction with DELETE

`DELETE From..To` may shift or invalidate the cursor. After a successful delete of
`From..To` (1-based, inclusive), when `Append_Mode` is false adjust `Insert_Point`:

- If `Insert_Point >= To` (cursor entirely after the deleted span): subtract the
  number of deleted lines — `Insert_Point := Insert_Point - (To - From + 1)`.
- If `From - 1 <= Insert_Point < To` (cursor inside the deleted span): move it to
  just before the span — `Insert_Point := From - 1`.
- If `Insert_Point < From - 1` (cursor before the span): unchanged.

Finally clamp `Insert_Point` to `[0, length]` (length after deletion). The cursor
never needs to flip to append-mode on DELETE; clamping suffices.

## Visibility

### INSERT confirmation

`INSERT` prints a one-line confirmation (interactive feedback):

- `Insertion point set at beginning.` (line 0)
- `Insertion point set after line 3.` (line n)
- `Insertion point set at end (append).` ( `$` / bare / clamped )

### LIST marker

`LIST` marks the cursor with an arrow line at its location. Example with the cursor
after line 2:

```
1: USE data.csv
2: LET x = 1
   --> insertion point
3: PRINT x
```

- Cursor at beginning (line 0): the `--> insertion point` line prints *before*
  line 1.
- Append mode: the `--> insertion point` line prints *after* the last entry.
- Empty buffer: unchanged (`(Empty program buffer)`); no arrow.

The arrow line is informational only and is not itself a buffer entry (it carries
no line number and is never renumbered).

## Code changes (sdata crate only)

| Area | File | Change |
|---|---|---|
| Lexer | `src/lexer/sdata-lexer.ads` / `.adb` | Add `Token_INSERT` keyword; add `Token_Dollar` for a standalone `$`. |
| AST | `src/ast/sdata-ast.ads` | Add `Stmt_PROGRAM_INSERT` with `Insert_At_End : Boolean`, `Insert_Line : Natural`, and `Insert_Bad : Boolean` (negative/invalid argument). |
| Parser | `src/parser/sdata-parser.adb` | Parse `INSERT [n｜$]` (peek numeric → `Insert_Line`; `Token_Dollar`/none → end; leading `Token_Minus` [+ number] → `Insert_Bad`). |
| Interpreter | `src/sdata-interpreter.adb` | `Append_Mode` / `Insert_Point` state; `Add_To_Active_Program` honors the cursor; new `Execute_Program_Insert`; add `Stmt_PROGRAM_INSERT` to `Is_Immediate`; reset cursor in `Clear_Active_Program`; adjust cursor in `Execute_Program_Delete`. |
| Interpreter | `src/sdata-interpreter-execute_metadata.adb` | `Stmt_LIST` prints the `--> insertion point` marker. |
| Reserved kw | `src/sdata-reserved_keywords.adb` | Add `"INSERT"` (mirrors the lexer keyword list). |

`Add_To_Active_Program` already increments `Pending_Deferred`; that is unchanged —
an inserted statement is still pending until the next RUN. Position in the buffer
does not affect pending semantics.

## User-facing references (must update together)

Per `CLAUDE.md` ("Keeping the user-facing surface in sync"):

1. **HELP** — `src/sdata-help.adb`: new `Command: INSERT` topic; mention `INSERT`
   in the `LIST` topic and command summaries alongside `DELETE`. Regenerate
   `tests/expected/help_all.out` and any `options_display` / `*_options` snapshot
   that enumerates the affected output.
2. **Man page** — `man/man1/sdata.1`.
3. **Design doc** — `doc/design.md` (authoritative language spec).

## Testing

- **Unit (parser/dispatch):** `INSERT`, `INSERT 0`, `INSERT n`, `INSERT $`,
  out-of-range clamp — assert the parsed `Stmt_PROGRAM_INSERT` fields and cursor
  state transitions (mirrors the TRANSPOSE `TT-01..TT-06` pattern).
- **Integration (`.cmd` + expected output):**
  - Insert at beginning, middle, end; verify resulting `LIST` order and marker.
  - Multiple consecutive inserts advance the cursor (correct order).
  - Cursor persists across `RUN`; `NEW` resets it.
  - `DELETE` cursor adjustment (before / inside / after the deleted span).
  - Out-of-range warning + clamp.
- All 202 existing integration tests plus the new ones must pass; `make check`
  green before commit.

## Out of scope (YAGNI)

- **`CHANGE` command** (in-place replacement of a line) — the project owner plans
  to add this after 1.0; not part of this work.
- Editing/replacing a line in place (today: `DELETE` then `INSERT`).
- Moving existing lines within the buffer.
- Persisting or displaying a cursor history.
