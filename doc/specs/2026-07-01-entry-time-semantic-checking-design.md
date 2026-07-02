# Entry-Time Semantic Checking of Deferred Statements

**Date:** 2026-07-01
**Status:** Design approved; implementation pending
**Component:** sdata interpreter (parser, deferred-statement queue) + sdata-core evaluator

## Problem

Deferred-execution statements (`LET`, `SET`, `PRINT`, `IF`, `FOR`, `WHILE`,
`WRITE`, `DELETE`) are validated for type compatibility only during per-record
execution inside the data-step loop, at `RUN` time. A statement with a
guaranteed type error is accepted silently when entered and fails only when a
record is processed:

```
sdata> use mock
sdata> names
Permanent Variables (Table Columns):
ID NAME$ SALARY
sdata> let foo=name$
sdata> run
Error: Type mismatch for variable foo: Cannot assign VAL_STRING to VAL_NUMERIC
```

The information needed to reject `let foo=name$` exists the moment it is
entered (`NAME$` is known to be a string column). The error should surface
then. More generally, any check that can be performed before `RUN` — rather
than per-record during `RUN` — should be.

### Current validation timeline (as-is)

- **Parse time (both modes):** only two checks. (1) A *literal*-assignment
  suffix conflict, e.g. `let foo$ = 123` (`sdata-parser.adb:2148`, Issue #31);
  (2) unknown `AGGREGATE` function names. In batch, a parse-time rejection
  discards the whole script before any command runs (see
  `tests/type_check_early.cmd`).
- **RUN entry:** variable slots are resolved to PDV indices
  (`Resolve_Expr_Indices`, `sdata-interpreter-resolve_expr_indices.adb`). No
  type checking.
- **Per record, during RUN:** all type checking — `Coerce_For_Scalar`
  (`sdata-interpreter-execute_assignment.adb:96`) raises the assignment
  type-mismatch error once per record. Unknown functions in expressions
  **never** error; they silently return `Val_Missing`
  (`sdata_core-evaluator.adb:357`).

The AST is untyped; there is no symbol table at parse time. Column types are
inferred from data at `USE` time.

## Key enabling insight: the schema is (or should be) stable before RUN

Naive entry-time type checking appears unsound because a deferred statement can
outlive the table it was written against. But the design spec already says it
should not: `doc/design.md:960` (the `USE` command reference) states —

> *"Any DROP, KEEP, LET, or REPEAT statements are canceled when a new dataset
> is read in."*

The **implementation does not honor this**. `Clear_Active_Program` is called
only in the `NEW` handler (`sdata-interpreter-execute_declarative.adb:793`); the
`USE` (`Execute_USE_Single`/`Execute_USE_Multi`) and `REPEAT` (`Stmt_REPEAT`,
`execute_declarative.adb:767`) handlers never clear the deferred program. The
comment at `sdata-interpreter.adb:99` ("reset to append only by NEW") documents
the bug, not the intent.

This is a latent spec violation independent of the type-checking feature. Once
`USE`, `REPEAT`, and `NEW` all clear the deferred queue, the schema is **stable
from the moment a deferred statement is entered until it runs**, which makes
entry-time semantic checking sound.

## Design

Two parts: a prerequisite spec-compliance fix, then the semantic analyzer.

### Part 1 — `USE` and `REPEAT` clear the deferred program (prerequisite)

- `Execute_USE_Single` and `Execute_USE_Multi` call `Clear_Active_Program` and
  reset the `Pending_Deferred` counter, exactly as `NEW` does — **without**
  disturbing the table/columns just loaded by the `USE`.
- The `Stmt_REPEAT` handler (which already clears the table and input columns)
  additionally calls `Clear_Active_Program` and resets `Pending_Deferred`.
- Correct the comment at `sdata-interpreter.adb:99` to name `USE`, `REPEAT`,
  and `NEW` as the reset points.

`REPEAT` is the other input-source command and is mutually exclusive with `USE`
(`design.md:618–624`), so clearing the queue on both is symmetric.

**Compatibility:** existing tests that mix multiple `USE`s with `LET` all queue
their deferred statements *after* the `USE` (e.g. `select_end_test.cmd`,
`save_multi_with_if.cmd`) or bracket blocks with explicit `NEW`. Clearing on
`USE`/`REPEAT` discards only statements queued *before* it — the stale-schema
statements this feature targets. `make check` must confirm no regression.

### Part 2 — The semantic analyzer

A single check routine, four checks, invoked at two points.

**Guiding principle — sound, not complete:** reject only on a *provable*
violation. Where an expression's result type cannot be statically determined
(e.g. a builtin whose return type depends on runtime values, or an operand that
resolves to `Val_Missing`), the analyzer **defers to runtime rather than
guessing**. This guarantees no false positives.

#### Static type environment

A symbol table mirroring what the PDV will contain at `RUN`:

- **Seed:** current table columns (with their inferred types), session `SET`
  variables already defined, and declared arrays — both actual (`DIM`) and
  virtual (`ARRAY`).
- **Extend:** walk the queued deferred statements in order; each `LET`/`SET`
  that introduces a new name adds it (type from the suffix rule / inferred RHS
  kind), and each `ARRAY`/`DIM` registers array names and element names.
- **Scope for undefined-variable checking is the whole queued program**, so a
  reference to a name created by a *later* queued statement is not flagged
  (forward references are legal in the per-record model).

Because `USE`/`REPEAT`/`NEW` clear the queue, the environment always reflects a
single, current schema.

#### The four checks (all hard errors)

1. **Assignment type mismatch.** Generalizes the Issue #31 literal check from
   literals to full expressions. A new `Static_Result_Kind (Expr)` companion to
   `Evaluate`, living in `sdata-core`'s evaluator (where `Expression` nodes are
   defined), infers an expression's result kind or reports *unknown*. The
   analyzer compares it against the target's expected kind using the existing
   `Get_Expected_Kind` rules (`$` → string, `%` → integer, else numeric; integer
   → numeric promotion allowed). *Unknown* result kind ⇒ defer.
2. **Unknown function name.** A genuine function-call node naming a function not
   in the evaluator dispatch table is rejected. **Array subscripts (`x(1)`) are
   not function calls and are never flagged**; array names live in the
   environment. Schema-independent.
3. **Function arity.** A known builtin invoked with the wrong number of
   arguments is rejected. Requires per-function arity metadata surfaced from the
   evaluator. Schema-independent.
4. **Undefined variable reference.** A name used in an expression that is not a
   table column, session variable, array (actual or virtual), or created
   anywhere in the queued program is rejected. Schema-dependent.

This is a behavior change for checks 2 and 4: today `let x = foobar()` and
references to never-defined names silently yield `Val_Missing`. They now error.

#### Invocation

- **Interactive (REPL):** run the full analyzer at statement entry — a prior
  `USE` has already executed, so the schema is live. Reject the offending line
  and do not queue it.
- **Batch:** the whole script is parsed before any command runs, so at parse
  time no `USE` has executed and the schema is unknown. Therefore:
  - **Schema-independent checks (2, 3)** run at **parse time** and reject the
    whole script early, matching the existing Issue #31 behavior.
  - **Schema-dependent checks (1, 4)** run as a **pre-`RUN` static pass** over
    the queued statements. By the time the execution walker reaches a `RUN`, the
    preceding `USE` has executed and the schema is live. The pass reports all
    such errors before record 1 is processed.

### Code structure

- New sdata unit for the analyzer and the static type environment (e.g.
  `sdata-interpreter-check_deferred` or a `sdata-semantics` child package).
- `Static_Result_Kind` and per-function arity metadata added to
  `sdata_core-evaluator`.
- The analyzer reuses the existing `Get_Expected_Kind` / `Coerce_For_Scalar`
  type rules rather than duplicating them.

## User-facing surface (update all three, per CLAUDE.md)

1. **`doc/design.md`** — retain the `USE` cancellation clause; add the `REPEAT`
   symmetry, and a new subsection specifying entry-time semantic checking (the
   four checks, hard-error severity, and the sound-not-complete deferral rule).
2. **`man/man1/sdata.1`** — document the checks and when they fire.
3. **`src/sdata-help.adb`** — update the relevant HELP topic(s); regenerate
   `tests/expected/help_all.out` and any `*_options` expected output affected.

## Testing

- **Integration `.cmd` tests** — one reject case per check, plus:
  - defer/pass cases: dynamic-result-type expression not rejected; forward
    reference not flagged; array subscript `x(1)` not flagged as unknown
    function.
  - `USE` clears a previously queued `LET` (Part 1); `REPEAT <n>` clears a
    previously queued `LET` (Part 1).
  - interactive-entry rejection vs batch pre-`RUN` rejection.
- **Unit tests** — `Static_Result_Kind` result-kind inference (including
  *unknown* cases) and the static type environment (seed + extend + array
  handling).
- **Full gate** — `make check` (sdata) **and** `cd ~/Develop/data-vandal &&
  make check`, because Part 1 and `Static_Result_Kind` touch `sdata-core`.
  Build `sdata-core` first (`cd ~/Develop/sdata-core && alr build`).

## Risks / migration

- **Unknown-function and undefined-variable hard errors are behavior changes**
  (silent-missing → error). Grep existing tests and any sample scripts for
  deliberate reliance on the old silent-missing behavior before landing.
- The analyzer must reliably distinguish function-call nodes from array
  access, and must honor `ARRAY`/`DIM`/virtual arrays in the environment, or it
  will wrongly flag legitimate array references.
- Partial inference must err toward *unknown ⇒ defer*; a too-eager inferer that
  reports a concrete kind where it should not would reintroduce false positives.

## Out of scope

- Full static type inference over all runtime-dynamic constructs (deliberately —
  the analyzer is sound but intentionally incomplete).
- Domain checks that are inherently runtime (division by zero, array bounds,
  `Inf`→integer) remain at execution time.
