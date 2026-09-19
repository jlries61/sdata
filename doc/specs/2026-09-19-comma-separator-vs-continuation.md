# Comma as separator vs. comma as continuation mark — discussion draft

**Date:** 2026-09-19 | **Status:** Implemented -- see ADR-080 (decisions in section 8; this file is the discussion and probe record)
**Origin:** milestone `2026-09-19-post-tables-stats-parity`, finding SK-4 / refactor item R3
(`.ssd/milestones/2026-09-19-post-tables-stats-parity/`). While planning R3 (consolidate the 13
`Skip_Continuation_Comma` call sites) it became clear that the underlying *rules* are unsettled, so
the refactor should wait on them.

## 1. What the spec says today

Almost nothing. `doc/design.md` §5.4 (repeated at §1166) has one sentence:

> "A statement ending with a comma shall be continued to the next line."

Nothing states where a comma is a *separator*, or whether a comma is legal at all in a
space-separated grammar (`PRINT`, `TABLES`, option loops). The behavior that exists comes from the
lexer (`src/lexer/sdata-lexer.adb`, ~lines 116-200), 11 call sites of `Skip_Continuation_Comma` in
`src/parser/sdata-parser.adb`, and ADR-072 (which fixed one bug, sdata#90).

### How the code works

- The lexer sees a `,` followed only by spaces/tabs/CR and then a newline, and treats it as a
  *continuation*. It then swallows the newline **and any further blank lines, comment lines, and
  bare `,` lines** before returning the next token.
- It still returns the comma itself as a normal `Token_Comma` (ADR-072). This is deliberate: it was
  discarding it before, which broke comma-delimited grammars split across lines (`USE a(...),\n b(...)`,
  `SUM(1, 2,\n 3)`, `KEEP=`/`DROP=`/`RENAME=` lists).
- A mid-line comma and a continuation comma are both `Token_Comma`; the parser cannot tell them
  apart. (The lexer has a flag, `Just_Emitted_Continuation_Comma`, but it is used only for the REPL
  `..>` prompt.)
- In grammars with **no** comma role, the parser calls `Skip_Continuation_Comma` before each "is
  there more?" decision. That procedure skips **every** `Token_Comma`, mid-line ones included.
- So the same token is a *separator* in comma-delimited grammars and a *continuation mark* in
  space-separated ones, and in the latter case any comma anywhere is silently discarded.

## 2. Observed behavior (17 probes, run against the real `bin/sdata` on 2026-09-19)

Each probe opened `tests/data/display_rows.csv`, ran `RUN`, then executed the line(s) shown.
(`PRINT` is a deferred command, so those probes also needed a trailing `RUN`.)

| # | Input | Result | Note |
|---|---|---|---|
| 1 | `PRINT 1, 2, 3` | prints `1 2 3` | comma treated as whitespace |
| 2 | `DISPLAY /FIRST=2, /LAST=1` | accepted | mid-line comma between options |
| 3 | `DISPLAY ID, /FIRST=2` | accepted | mid-line comma before an option |
| 4 | `STATS ID, /STATS=N` | accepted | same |
| 5 | `TABLES ID, ID*ID` | accepted | comma between requests |
| 6 | `PRINT 1,,  2` | **error**: `Unrecognized command "2"` | two commas on one line |
| 7 | `PRINT 1,` / *(blank line)* / `PRINT 2` | **error**: `Unrecognized command "2"` | continuation swallowed the blank line and joined the next statement |
| 8 | `PRINT 1,` then `RUN` (no blank line) | no output at all | `RUN` was absorbed as an argument to `PRINT` |
| 9 | `PRINT 1, -- note` / `2` | **error**: `Unrecognized command "2"` | a comment between the comma and the newline cancels the continuation |
| 10 | `PRINT 1 -- note,` / `PRINT 2` | fine | a comma inside a comment is inert |
| 11 | a line containing only `,` between two `PRINT`s | silently ignored | |
| 12 | `PRINT 1` / `, 2` | **error**: `Unrecognized command "2"` | a leading comma on the next line is not a continuation |
| 13 | `LET X=1,` / `PRINT X` | both run normally | trailing comma after a *complete* statement is a no-op (pinned by `tests/orphan_continuation_comma.cmd`) |
| 14 | `PRINT SUM(1, 2,` / `3)` | `6` | separator role works |
| 15 | `PRINT 1,` / `2` | prints `1 2` | ordinary continuation works |
| 16 | `KEEP ID,` / `ID` | works | separator + continuation, comma-delimited list |
| 17 | `PRINT "a,"` / `PRINT 2` | fine | comma in a string is inert |

## 3. What is unsettled

1. **What may follow a continuation comma.** Blank lines and comment lines are skipped (probes 7, 8).
   A forgotten trailing comma silently glues the *next statement* onto this one, and the resulting
   error appears elsewhere, or not at all.
2. **A trailing comment after the comma breaks the continuation** (probe 9). `KEEP A, -- key` /
   `B` is a natural way to write a list.
3. **Mid-line commas in comma-free grammars are accepted silently** (probes 2-5). This may be an
   accident rather than a decision. It also makes `,,` an error in one place (probe 6) while stray
   commas are ignored in another (probe 11).
4. **The rule is undocumented**, so any change is a language-visible decision that needs the usual
   synchronized updates (design.md, HELP, man page, an ADR) and consideration of existing scripts.

## 4. Decisions needed

**D1. A mid-line comma in a comma-free grammar** (`STATS ID, /STATS=N`, `DISPLAY ID, /FIRST=2`):
- (a) Keep lenient: comma is whitespace there.
- (b) Make it an error.
- *Lean: (b)* — the only way to make stray and doubled commas consistently wrong. Cost: breaks any
  script relying on the leniency (probably few; `PRINT`'s tolerance is documented only by ADR-072's
  empirical note, not by design.md).

**D2. What may follow a continuation comma:**
- (a) Anything: blank lines and comment lines are skipped (today).
- (b) Only the next physical line; a blank line ends the statement.
- *Lean: (b)* — removes the "glued the next statement" failure (probes 7, 8).

**D3. A comment between the comma and the newline** (`KEEP A, -- key`):
- (a) Still a continuation.
- (b) Not a continuation (today).
- *Lean: (a)* — "a statement ending with a comma" plausibly includes a trailing comment.

**D4. A comma after a *complete* statement** (`LET X=1,`):
- (a) Legal no-op (today; deliberately pinned by `orphan_continuation_comma.cmd`).
- (b) An error.
- No strong lean; (a) is a conscious existing decision, so changing it would be a reversal.

**D5. A dangling comma at the end of input** (batch mode):
- (a) Silent (today, in effect: the next line absorbs it, probe 8).
- (b) An error: "statement ends with a continuation comma but no line follows".
- *Lean: (b)*, once D2 is settled.

## 5. Implications for R3

R3 was scoped as "route the 11 `Skip_Continuation_Comma` call sites through one helper". That
should wait until D1-D5 are decided, because if D1 goes strict there is a cleaner design:

- The lexer already knows which commas end a line. Have it emit a distinct
  `Token_Continuation_Comma` (or keep `Token_Comma` and add a `Continuation : Boolean` field on the
  token).
- **Comma-delimited grammars** treat both kinds as a separator — behavior unchanged, so the sdata#90
  cases keep working.
- **Comma-free grammars** skip only the continuation kind and reject a mid-line comma.
- That replaces "11 places must each remember to call the skip" with one rule enforced at the token
  level, and it is where D2/D3/D5 would also be implemented (in the lexer's continuation logic).

Note the **earlier recommendation to "swallow the comma in the lexer" was wrong** and is retracted
in `skeptic-before.md`: the lexer must keep returning the comma for comma-delimited grammars. The
distinct-token design above is compatible with that.

If D1 stays lenient (a), R3 shrinks back to the parser-side helper planned originally.

## 6. If a strict option is chosen — what a change would involve

- `doc/design.md` §5.4: replace the one-sentence rule with a real specification (both roles, what
  may follow a continuation comma, what happens on a stray comma).
- `src/sdata-help.adb` and `man/man1/sdata.1`: matching wording; regenerate
  `tests/expected/help_all.out` if HELP text changes.
- A new ADR (next number is 080), recording the decision and the reversal of any pinned behavior.
- Tests: the existing `*_trailing_comma_*` / `*continuation*` tests (about 36) are the safety net;
  new tests for each D-decision, including *negative* tests (the newly-rejected inputs).
- **Compatibility:** stricter rules can break existing user scripts. Consider whether a stricter
  rule should warn first (a release with a warning, then an error) rather than error immediately.
- Sequence: decisions → ADR + spec text → tests → implementation. R3's mutation coverage audit of the
  11 call sites (its step 1) is still useful and independent of the decisions.

## 7. Reproducing the probes

The probe scripts lived in the session scratchpad; each has this form:

```
USE "tests/data/display_rows.csv"
RUN
<the line(s) from the table>
RUN            (only for PRINT probes)
QUIT
```

Run with `bin/sdata <file>.cmd`.

## 8. Decisions (made 2026-09-19)

| # | Decision |
|---|---|
| D1 | **(b) strict**, scoped to the *comma-free positions* (see below). A mid-line comma there is a parse error. |
| D1 scope | **Option loops only.** Strict applies where the parser now calls `Skip_Continuation_Comma`: slash-option loops (USE, SAVE, TRANSPOSE, STATS, TABLES, DISPLAY), the TABLES request list, the AGGREGATE `outvar=fn(invar)` list. **PRINT/NOTE, function arguments, KEEP/DROP/RENAME/BY lists, USE dataset lists and other comma-delimited grammars are unchanged.** PRINT's comma is documented as a legal, optional separator (it is standard BASIC and ~15 existing test files use it). |
| D2 | **(b)** a continuation comma continues onto the next physical line only; **a blank line ends the statement.** |
| D2 detail | **Comment-only lines are skipped**: they are invisible and do not end the statement. Only a truly blank (whitespace-only) line does. |
| D3 | **(a)** a trailing `--` comment after the comma still counts as a continuation. |
| D4 | ~~**(a)** a trailing comma after a *complete* statement (`LET X=1,`) stays a legal no-op~~ **REVERSED at the round-1 gate (2026-09-19):** a comma never separates statements, and an end comma always joins the next line, even after a complete statement. `LET X=1,` / `PRINT X` is `LET X=1 PRINT X`, a syntax error; `tests/orphan_continuation_comma.cmd` now expects that error. |
| D5 | **(a)** a dangling comma at the end of input stays silent. |
| Repeated commas | **Keep swallowing**: extra comma-only lines directly after a continuation (`A,` / `,` / `B`) are still silently swallowed, as ADR-072 left them. A blank line between them still ends the statement. |
| Rollout | **Error immediately**, no warning release. The rejected forms were never documented and the project is pre-release. |

Evidence for the scope decision: the documented grammar of AGGREGATE and TABLES is space-separated
(`design.md` lines ~865 and ~1119, HELP lines ~290 and ~361), and every comma in their tests sits
inside parentheses (`PCTL(X, 50)`) or at the end of a line (`TABLES NAME$,`). No existing test
uses a mid-line comma in a comma-free position.

## 9. The resulting rules (proposed spec text, for review)

1. **Continuation comma.** A comma that is followed, on the same line, only by whitespace and/or
   a `--` comment before the end of the line is a *continuation comma*. Any other comma is a
   *mid-line comma*.
2. **Extent.** After a continuation comma the statement continues on the next physical line.
   Comment-only lines are ignored. A comma-only line directly after a continuation is ignored.
   A blank line ends the statement.
3. **Comma-delimited grammars** (function arguments, `KEEP`/`DROP`/`RENAME`/`BY` lists, `USE`
   dataset lists, `ARRAY`/`DIM` subscripts, `PRINT`/`NOTE` arguments where the comma is optional)
   are unchanged: a comma is a separator whether or not it ends a line.
4. **Comma-free positions** (slash-option loops, TABLES request list, AGGREGATE outvar list): only a
   continuation comma is allowed, and it is ignored. A mid-line comma is a parse error naming the
   comma and saying it may only end a line here.
5. **Complete statement.** *(Reversed at the gate.)* A comma in the middle of a line after a complete statement is a syntax error. A continuation comma appends the next line even after a complete statement, so `LET X = 1,` / `PRINT X` is a syntax error; a comma before a blank line or end of input joins nothing and is harmless.
6. **End of input.** A dangling continuation comma at the end of input is silently accepted.

### What this changes, probe by probe (section 2)

| Probe | Today | After |
|---|---|---|
| 2 `DISPLAY /FIRST=2, /LAST=1` | accepted | **error** (mid-line comma between options) |
| 3 `DISPLAY ID, /FIRST=2` | accepted | **error** |
| 4 `STATS ID, /STATS=N` | accepted | **error** |
| 5 `TABLES ID, ID*ID` | accepted | **error** |
| 7 `PRINT 1,` / *(blank)* / `PRINT 2` | error | **works**: the blank line ends the first statement, both run |
| 9 `PRINT 1, -- note` / `2` | error | **works**: prints `1 2` |
| 1, 6, 10-17 | unchanged | unchanged |
| 8 `PRINT 1,` then `RUN` (no blank line) | `RUN` silently discarded | **syntax error** — see section 11: the lines are joined into `PRINT 1 RUN`, and that is invalid |

Probes 2-5 are the only newly-rejected inputs; 7 and 9 become valid.

## 10. Open implementation questions (for the design step, not for you)

- **`Parse_Variable_List` and a comma before `/`.** `STATS ID, /STATS=N` and `DISPLAY ID, /FIRST=2`
  currently work partly because the variable-list parser consumes the comma. Under rule 4 that comma
  must be rejected (unless it is a continuation comma, as in `DISPLAY ID,` / `/FIRST=2`, which must
  keep working). Needs a look at how the list parser treats a trailing comma.
- **Distinguishing the two comma kinds.** Simplest approach: a `Continuation : Boolean` field on the
  token record (comma-delimited grammars keep checking `Kind = Token_Comma`, so they are untouched),
  set by the lexer. This is preferable to a new token kind, which would touch every comma-checking
  site.
- **Lexer changes** implement rules 1-2: stop consuming blank lines after a continuation comma
  (leave the LF to be returned as a normal `Token_Newline`), allow a `--` comment between the comma
  and the newline, and keep skipping comment-only lines and comma-only lines.
- **REPL.** A blank line at the `..> ` prompt after a trailing comma now ends the statement rather
  than being swallowed; check `Ended_With_Continuation` / `Continued_At_EOF` behavior (ADR-072 records
  that area as the highest-risk part of the lexer).
- **Revised R3.** With a `Continuation` flag on the token, the 11 `Skip_Continuation_Comma` call sites
  collapse to one helper that skips continuation commas and raises the rule-4 error on a mid-line
  comma. That is R3, now with a defined behavior rather than a pure refactor, so it becomes a
  feature (ADR-080), not a refactoring PR.

## 11. The "naive approach" and what it requires (2026-09-19)

**Position taken:** a continuation comma simply joins the lines. `PRINT 1,` / `RUN` is then
`PRINT 1 RUN`, which is an ordinary syntax error. No special protection for that case is wanted.

Investigating this found that `PRINT 1 RUN` is **not an error today, even on one line with no comma
at all**. Two separate causes:

1. **`Parse_Primary` swallows tokens it cannot use.** Its `when others` branch
   (`src/parser/sdata-parser.adb`, ~lines 415-522) calls `Get_Next_Token` *before* deciding the
   token is not an operand, then returns null. The token is gone. `PRINT 1 RUN`, `PRINT 1 LET`,
   `PRINT 1 SELECT`, `PRINT 1 DISPLAY`, `PRINT 1 USE` and `PRINT 1 PRINT` all silently discard the
   keyword (`PRINT 1 FOO` and `PRINT 1 IF` are errors only because those parse as identifiers and
   fail at run time as "undefined variable"). This contradicts `design.md` §8.3, which says a name
   colliding with a reserved keyword must be written in backticks.
2. **Nothing requires a terminator between statements.** `Parse_Program` and `Parse_Block` call
   `Parse_Statement` in a loop, and `Parse_Statement` skips leading colons, newlines and commas. So
   `LET X = 1 PRINT X` on one line is two statements today. The naive reading needs this to be a
   syntax error.

**Both must be fixed** for `PRINT 1 RUN` to error: fixing only cause 1 would make `RUN` parse as a
new statement in the middle of the line.

**Measured blast radius (throwaway prototype, reverted).** Rule: after a statement, the next token
must be a newline, colon, end of input, a comma (so D4 still works), or a block-structure keyword
(`ELSE`, `ELSEIF`, `NEXT`, `WEND`, `UNTIL`, `END`, `CASE`, `WHEN`, `OTHERWISE`); the check is skipped
when the statement already consumed its own newline or colon (tracked with a `Last_Kind` field on
the lexer context).

- First attempt, without the "already consumed its terminator" exemption: **44 of 616 tests
  failed**, all false positives (the statement had consumed its newline, so the next token was just
  the first token of the next line).
- With the exemption: **all 616 pass.** No existing test depends on statements running together.
- Probes with the prototype: `LET X = 1 PRINT X` (one line) becomes a syntax error;
  `LET X = 1 : PRINT X`, single-line `IF ... THEN PRINT 1 ELSE PRINT 2`, ordinary continuation
  (`PRINT 1,` / `2`) and the D4 orphan comma (`LET X=1,` / `PRINT X`) all still work.
- **The prototype did not yet make `PRINT 1 RUN` an error**, because of cause 1: the `RUN` was
  already consumed and lost by `Parse_Primary`. That is the second half of the fix.

**Language-visible consequence:** juxtaposed statements on one line without a `:` become errors.
This is a change beyond the comma rules; it needs its own paragraph in `design.md` and the ADR.

**Interaction with the other decisions:** D4 (a comma after a complete statement is a legal no-op)
is unaffected — the comma is skipped as noise at the start of the next statement, and the next
statement starts on the next line. D2's blank-line rule and the lexer changes are still to do;
until they are, `PRINT 1,` / *(blank)* / `PRINT 2` reports the wrong token (`"2"`) in the prototype.
