# Quoted Identifiers for Reserved-Keyword Column Names

**Date:** 2026-05-30 (scope reconciled 2026-06-17)
**Status:** Approved for implementation — scope reconciled in the `/ssd feature` design session 2026-06-17 (see "Implementation reconciliation" below)
**Scope:** sdata + data-vandal interpreters; one additive sdata-core helper + toggle

> **Implementation reconciliation (2026-06-17).** The `/ssd feature` design
> session locked the deferred scope decisions and the cross-crate plan. Where
> this section and the original design body below disagree, **this section
> wins** — the body is retained for its still-accurate per-component detail.
>
> **Decisions locked:**
>
> 1. **Both crates this cycle** (sdata *and* data-vandal get quoted identifiers
>    and the reserved-keyword warning). The lexer/AST/parser changes are
>    implemented twice (ADR-040: each consumer owns its grammar).
> 2. **Warning helper promoted to sdata-core** as the genuinely-shareable
>    sliver: `Warn_Reserved_Columns (T : Table; Keywords : <upcased set>)`.
>    Additive to sdata-core's public surface, therefore pin-safe for
>    `consumer-tests.yml`. Each consumer passes its own (grammar-specific)
>    reserved-keyword list.
> 3. **Warning gating lives *inside* `Warn_Reserved_Columns`** (single
>    authority), keyed on a new shared runtime toggle
>    `Config.Runtime.Options_Warn_Reserved : Boolean := True`, with a getter and
>    an `Internal.Set_…` setter, surfaced by a shared
>    `Execute_OPTIONS_WarnReserved (Value : Boolean)`.
> 4. **`OPTIONS WARNRESERVED YES|NO` (default YES)** is the suppression control.
>    sdata wires it into its existing OPTIONS dispatch + no-arg display.
>    data-vandal **has no OPTIONS command today**
>    (`data_vandal-interpreter.adb`: *"even though data-vandal has no OPTIONS
>    command today"*), so a **new OPTIONS command subsystem is built in
>    data-vandal** and exposes **`WARNRESERVED` only** this cycle (not the full
>    CSVDLM/HEADER/CHARSET key set — those may be added later).
>
> **Field-name correction:** the helper sketches below reference `T.Text_Len`;
> the actual lexer `Token` record field is `Length` (`src/lexer/sdata-lexer.ads`).
> The token type is `SData.Lexer.Token`. Implementations use the real names.
>
> **Build sequence — three independently-shippable phases (SSD iterations):**
>
> - **P1 (sdata + sdata-core):** quoted-id lexer+parser in sdata; sdata-core
>   `Warn_Reserved_Columns` helper, `Options_Warn_Reserved` toggle, and
>   `Execute_OPTIONS_WarnReserved`; sdata USE-time warning at both call sites
>   (single-dataset after `Execute_USE`, multi-dataset after
>   `Install_To_Current`); `OPTIONS WARNRESERVED` key + display in sdata; sdata
>   docs (HELP + `help_all.out` snapshot + man page + `design.md`) and tests.
>   Ships the entire sdata story.
> - **P2 (data-vandal):** quoted-id lexer+parser in data-vandal; data-vandal
>   USE-time warning (reuses the shipped sdata-core helper; always-on since
>   data-vandal cannot yet change the toggle); data-vandal tests.
> - **P3 (data-vandal):** new OPTIONS command subsystem in data-vandal
>   (`Token_OPTIONS`, AST node, parser, interpreter dispatch, no-arg display)
>   wiring `WARNRESERVED`; data-vandal docs (man page + `help.adb`).
>
> Each phase must leave all three crates green per the CLAUDE.md cross-crate
> gate (`sdata-core` build, sdata `make check`, data-vandal `make check`).

---

**Original design body (2026-05-30) — retained for component detail:**

**Date:** 2026-05-30
**Status:** Approved (design phase) — execution deferred
**Scope:** sdata interpreter only; no sdata-core changes

> **Scope addendum (2026-06-17): data-vandal also wants this capability.**
> The design body below is written for sdata and stands as-is. Extending it to
> data-vandal does **not** move work into sdata-core: per ADR-040, the lexer,
> AST, and parser are deliberately *not* in sdata-core — each consumer owns its
> complete grammar. data-vandal has its own parallel stack
> (`data-vandal/src/lexer/`, `…/parser/`, `…/ast/`), so the lexer-token +
> parser-site changes here must be **implemented a second time** against
> data-vandal's lexer/parser. The *design* is shared; the *code* is duplicated,
> and sdata-core work is essentially zero.
>
> One exception worth revisiting at implementation time: the **USE-time
> reserved-keyword warning** (see that section) was deliberately kept sdata-only
> "since data-vandal doesn't need it." That rationale no longer holds. Since the
> warning logic just walks a `Table` (which *is* in sdata-core) against a keyword
> set, consider promoting a generic `Warn_Reserved_Columns (Table, Keyword_Set)`
> helper into sdata-core, with each consumer passing its own (grammar-specific)
> reserved-keyword list. That is the one small genuinely-shareable sliver.
>
> The implementation session should reconcile this scope during the design step
> (e.g. `/ssd feature`): treat it as "design once, implement twice (sdata +
> data-vandal), plus one optional sdata-core warning helper," not as a
> sdata-core-centric change.

## Context

sdata reserves keyword tokens at the lexer level (`USE`, `BY`, `KEEP`, `DROP`,
`AS`, `IN`, `INTERLEAVE`, `JOIN`, etc.). When an input CSV/spreadsheet has a
column whose name collides with one of these, sdata cannot reference it from
the data step:

```
$ cat data.csv
ID,AS,USE
1,10,100

sdata> USE "data.csv"
sdata> NAMES
ID AS USE
sdata> PRINT AS
sdata> --  silently emits nothing
sdata> RENAME AS=X
Error: Unrecognized command "" at line 1
```

This applies to ALL reserved keywords, not just the four added by the
merge feature. Since sdata has no control over user input files, this is
a real usability gap.

## Goals

- Allow users to reference any column name regardless of keyword collisions
  via a quoted-identifier syntax: `` `name` ``.
- Emit a warning at USE time when a loaded column's name matches a reserved
  keyword so users discover the issue immediately rather than after silent
  data loss.

## Non-Goals

- Allow column names containing newlines or backticks. The escape mechanism
  is the column name only, not arbitrary strings.
- Change the internal representation of column names. They remain
  case-insensitively upper-cased.
- Change `NAMES` / error-message display: still print the bare name without
  backticks. Quoting is an input notation, not part of the name.
- Add quoted identifiers to anywhere a *string literal* is expected — only
  where an identifier is expected.

## Syntax

```
quoted_identifier := "`" {any-char-except-backtick-or-newline} "`"
```

Examples:
- `` `AS` `` — a column named AS
- `` `column with spaces` `` — a column with embedded spaces
- `` `a.b.c` `` — a column with dots

The content between backticks is the column/variable name verbatim,
upper-cased internally like any other identifier. `` `as` ``, `` `AS` ``,
and `as` (where allowed) all refer to the same name.

Empty backticks (``` `` ```) are a parse error.

Embedded newlines or backticks in the quoted region are a lex error
("unterminated quoted identifier" or "invalid character in quoted
identifier"). No escape mechanism is provided in this version.

## Lexer changes

Add a new token kind `Token_Quoted_Identifier`. The lexer recognises
the leading backtick, scans forward consuming characters until the
closing backtick, and returns a token whose `Text` / `Text_Len` fields
hold the content (excluding the backticks themselves).

Errors during scan (newline before closing backtick, EOF before
closing backtick, empty content) emit `Put_Line_Error` with a clear
message and produce a `Token_Bad` (or whatever the lexer's error token
convention is — match existing patterns for unterminated string
literals).

## Parser changes

Introduce two helpers:

```ada
function Is_Identifier_Token (T : Token_Type) return Boolean is
  (T.Kind = Token_Identifier or T.Kind = Token_Quoted_Identifier);

function Identifier_Text (T : Token_Type) return String is
  (T.Text (1 .. T.Text_Len));
```

Every parser site that currently checks `T.Kind = Token_Identifier`
must change to `Is_Identifier_Token (T)`. Every site that reads
`T.Text (1 .. T.Text_Len)` should use `Identifier_Text (T)` for
clarity (functionally identical).

### Affected sites (sample — implementation must find them all)

- Variable references in expressions (Parse_Expression's atom case)
- LHS of LET / SET assignments
- PRINT argument list
- KEEP / DROP / HOLD / UNHOLD argument lists (Parse_Variable_List)
- RENAME pair LHS and RHS (Parse_Rename_List)
- BY var list
- ARRAY / DIM name and constituents
- SORT var list
- Per-dataset `KEEP=`, `DROP=`, `RENAME=()`, `IN=` in
  `Parse_Spec_Options` (USE and SAVE)
- Per-target `IF=` expression — already uses `Parse_Expression`, so
  identifier-using sub-cases inherit the helper
- WRITE target list (which is itself a Variable_List)
- AS alias names in dataset specs
- Function call arguments (most via Parse_Expression)

The implementer should grep for `Token_Identifier` and adjust each
occurrence. Expected count: 15-25 distinct sites.

## USE-time warning

After every successful USE (single-dataset and multi-dataset paths), walk
the resulting table's columns and check each upper-cased name against
a static set of reserved keywords. For each match, emit one warning per
column:

```
warning: column "AS" matches a reserved keyword; reference it as `AS` or rename it
```

Implementation: a new function in sdata (NOT sdata-core, since data-vandal
doesn't need it) that takes the list of reserved-keyword strings and the
current table, and emits warnings. Called from `Execute_USE` after
`Install_To_Current` (multi-dataset) and after the legacy `Execute_USE`
returns (single-dataset).

The reserved-keyword list lives at sdata-only scope; do not push it to
sdata-core. A constant array or hash set of upper-case strings is fine.

## Display behavior

Unchanged: `NAMES`, error messages, and any other name-printing code
print bare names without backticks. Quoting is an input notation only.

This means a user seeing `NAMES` output of `AS` does not directly
learn they need backticks. The USE-time warning fills this gap.

## Backward compatibility

- Backtick is not currently used anywhere in sdata syntax. The
  lexer accepts it as a new state, no existing token changes.
- All existing scripts continue to parse unchanged. No `.cmd` test in
  the current suite uses backticks.
- A column whose CSV header contains a backtick — extremely unusual, but
  possible — would lex as multiple identifiers separated by quoted-
  identifier syntax. We accept this edge case as a parse error if the
  user tries to reference such a column; the workaround is to rename
  the column in the source.

## Open questions deferred to implementation

- Exact reserved-keyword list. The lexer body has the canonical list;
  the implementer extracts it once and exposes it as a constant array
  or hash set.
- Whether the USE-time warning should be suppressible via an OPTIONS
  setting. Default behavior: always warn. If suppression is wanted, an
  additional OPTIONS key can be added without affecting the rest of
  this design.

## Testing strategy

### Lexer unit tests

- Standalone backtick-quoted identifier: `` `AS` `` produces
  `Token_Quoted_Identifier` with `Text = "AS"`.
- Mixed case is preserved at the token level: `` `as` `` produces
  Text "as". (The parser upper-cases when looking up.)
- Spaces and dots: `` `col with space` `` and `` `a.b` `` produce the
  expected text.
- Unterminated: `` `AS\n `` and `` `AS`-at-EOF produce lex errors.
- Empty content `` `` `` produces a lex error.

### Integration tests (one per affected syntactic position)

Each test loads a small CSV with a reserved-keyword column, then uses
the quoted form in the relevant statement:

- `tests/quoted_id_print.cmd` — `PRINT \`AS\``
- `tests/quoted_id_let_lhs.cmd` — `LET \`AS\` = 5`
- `tests/quoted_id_rename.cmd` — `RENAME \`AS\`=ASCOL`
- `tests/quoted_id_keep.cmd` — `KEEP \`AS\``
- `tests/quoted_id_drop.cmd` — `DROP \`AS\``
- `tests/quoted_id_by.cmd` — `BY \`AS\``
- `tests/quoted_id_per_dataset_keep.cmd` —
  `USE "data.csv" (KEEP=\`AS\` ID)`
- `tests/quoted_id_per_dataset_rename.cmd` —
  `USE "data.csv" (RENAME=(\`AS\`=AS_COL))`
- `tests/quoted_id_save_if.cmd` — IF= filter referencing `` `AS` ``
- `tests/quoted_id_write_target_alias.cmd` —
  `SAVE "out.csv" AS \`AS\`` then `WRITE \`AS\`` (validates alias names
  can be quoted too)

### Warning test

- `tests/use_reserved_column_warning.cmd` — load a CSV with a column
  named `AS`; assert the warning message appears in stderr.

## Spec self-review

- **Coverage**: each requirement (syntax, lexer, parser sites, warning,
  display) has at least one integration test.
- **No placeholders**: the affected-parser-sites list is illustrative,
  not exhaustive — the implementation plan instructs the implementer
  to grep for all `Token_Identifier` occurrences. This is the right
  level of detail for a spec.
- **Scope**: appropriately bounded — one new token, one new helper
  pair, one new warning. No language semantics change beyond
  recognising more notations for existing identifiers.
- **Ambiguity**: the "what counts as a quoted identifier vs string
  literal" distinction is clear because the lexer is the arbiter —
  backticks are unambiguously quoted-identifier territory.
