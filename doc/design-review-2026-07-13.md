# Design Review — `doc/design.md` (language spec)

**Date:** 2026-07-13
**Scope:** the language design as recorded in `doc/design.md` only (not the
implementation architecture, not the ADRs).
**Method:** adversarial multi-lens review (codebase-skeptic). Lenses applied:
Kleppmann (data model / reproducibility), Wozniak (numeric / low-level), Evans
(domain model), Jobs (coherence / ergonomics), Fowler (spec architecture).
**Posture: ⚠ Drifting** — a sound data-step model, but the spec has drifted from
the implementation, delegates core semantics to an external proprietary
document, and carries a few ergonomic footguns inherited from its BASIC heritage.

Every finding below was grounded in the spec text and, where it concerns
behavior, verified against the running interpreter and/or source. Findings 1–3
were filed as individual issues; 4–7 were grouped into one spec-completeness
issue.

| Finding | Severity | Issue |
|---|---|---|
| 1. Platform-dependent float precision | 🔴 | [#54](https://github.com/jlries61/sdata/issues/54) |
| 2. Character-missing / empty-string conflation | 🔴 | [#55](https://github.com/jlries61/sdata/issues/55) |
| 3. `SET` silently drops a loaded column | 🔴 | [#56](https://github.com/jlries61/sdata/issues/56) |
| 4–7. Spec completeness (grouped) | ⚠ | [#57](https://github.com/jlries61/sdata/issues/57) |

---

## 1. 🔴 Platform-dependent float precision (§2.2) — Kleppmann / Wozniak

The spec says float width follows the architecture: 64-bit → IEEE double, 32-bit
→ IEEE single, 128-bit → quad. Two problems:

- **It isn't implemented.** The code uses Ada `Float` (32-bit single) on *every*
  platform (`sdata-core/src/sdata_core-values.ads:21`, `Num_Val : Float;`; the
  comment at `:51` confirms "single-precision Float exactly … only 6 significant
  digits"). The 9-significant-digit round-trip work in SAVE (v0.14.0) was a
  direct consequence of this 32-bit choice.
- **The design goal itself is wrong for a data tool.** Even implemented as
  written, *the same script would produce different numeric results on a 32-bit
  vs a 64-bit machine.* For a statistical data interpreter, cross-machine
  reproducibility is a primary requirement, and platform-dependent float width
  silently breaks it. "Match the native word size" is a systems-programming
  instinct that does not fit this domain.

**Reconsider:** mandate a **fixed** precision — IEEE 754 double (`Long_Float`) —
on every platform, and delete the architecture-dependent table in §2.2. This
closes the spec/code gap, makes results portable, and moves to the precision
most users assume. It is a data-model change (touches `sdata_core-values.ads` and
everything that reads `Num_Val`), so it warrants its own design pass.

## 2. 🔴 The empty string is both "missing" and a real value (§2.5, §3.6) — Evans

There is no way to represent a missing character value distinct from a
legitimately empty string — both are `""`. The spec contradicts itself, and the
implementation behaves as both depending on which function reads it:

```
REPEAT 1
LET S$ = ""
PRINT MISSING(S$)     -- 1   (treated as MISSING)
PRINT LEN(S$)         -- 0   (treated as a real empty string)
PRINT S$ + "x"        -- x   (concatenates as a literal empty string)
RUN
```

§2.5 / §3.6 define character-missing **as** `""`, while §2.5 also states "Null
strings (`""`) in string operations shall be taken literally." Those rules
conflict. Downstream logic that rests on this — BY-group distinctness,
`MISSING`/`NMISS`, `SELECT` filters — inherits the ambiguity.

**Reconsider:** decide what character-missing *is*. Either (a) commit to "empty
= always missing" and make string ops propagate it, or (b) introduce a distinct
character-missing sentinel and let `""` be a real empty string (the SAS
approach). Either is defensible; the current "neither" is the problem.

## 3. 🔴 The assignment *verb* silently changes storage class (§3.5) — Jobs

`LET` makes a name permanent (a table column); `SET` makes it temporary. So a
`SET` on a **loaded column** silently drops that column from the dataset:

```
# /tmp/sl.csv:  a,b / 1,2 / 3,4
USE "/tmp/sl.csv"
SET A = A * 10
SAVE "/tmp/sl_out.csv"
RUN
# -> Warning: Column 'A' dropped from table and converted to session variable.
#    sl_out.csv comes out malformed.
```

§3.5 specifies this ("Permanent → Temporary: If permanent variable redefined by
`SET`, it becomes temporary"), but the effect is data loss behind a warning — the
exit code is still 0, the same silent-corruption posture we hardened away from in
#50–#52. The choice of computation verb should not silently decide whether a
value reaches the output file.

**Reconsider:** at minimum, make demotion of a loaded/permanent column via `SET`
a hard error, not a warning. Better: reconsider whether storage class should be
coupled to the assignment verb at all, versus controlled explicitly by
`KEEP` / `DROP` / `/TEMP`. The malformed `SAVE` output also looks like a genuine
bug worth auditing independently of the design question.

## 4. ⚠ Core semantics delegated to Bywater BASIC 3.20's manual (§1.2, §7.3) — Fowler / Evans

**Operator precedence** — the most fundamental expression semantic — is specified
only as "As specified in BW BASIC documentation" (§7.3). Same for `FOR/NEXT`,
`DIM`, `DIGITS`, the `DELETE` line-editor. A reader cannot determine how
`a + b * c` parses from the authoritative spec without an effectively-unobtainable
proprietary manual.

**Reconsider:** inline the real precedence table and the actual semantics of
these commands into design.md.

## 5. ⚠ Keyword overloading (§5.3, §7.1) — Jobs / Fowler

`REPEAT` names both the record-generating command **and** the `REPEAT/UNTIL` loop
(§5.3 flags this itself). `DELETE` names both an immediate line-editor
(`DELETE <line>`) **and** a deferred record-delete. Two mental models per
keyword; the parser disambiguates by argument shape, but users won't.

**Reconsider:** rename one construct in each pair (a breaking change, so decide
deliberately).

## 6. ⚠ Overflow "shall fail" vs. the Inf that already exists (§2.4, §8.5) — Wozniak

§2.4 says float overflow "shall fail with an error message," and §2.4-note / §8.5
list IEEE Inf/NaN as *future* — but `IEEE_DIVIDE` and `MAXNUM()*2 → Inf` are
already implemented and propagate. The spec is behind its own code and internally
inconsistent.

**Reconsider:** state the overflow/Inf model once (likely option-controlled, as
`IEEE_DIVIDE` already implies) and move Inf out of "future extensions."

## 7. ⚠ A stated core requirement is already contradicted (§1.1 vs §2.1) — Fowler

§1.1 promises "No hard memory or dimensional constraints," but §2.1 documents a
hard ~2000-column disk-spill ceiling (plus the 64-char name limit and 32-bit
integer range elsewhere).

**Reconsider:** soften §1.1 to the truth, or commit to lifting the spill ceiling
(the long/EAV spill schema already noted as deferred).

**Doc hygiene:** pandoc-conversion artifacts survive — `shalfunctionl` (line 90),
`Execition` (line 779), "Looking blocks" (line 572, likely "Looping"). A
proofreading pass is warranted for the authoritative reference.

---

## Synthesis

**Dominant theme:** the spec is a *sound data-step design wearing two ill-fitting
inheritances* — a numeric model borrowed from systems programming
(platform-native float) and a program model borrowed from line-numbered BASIC
(`DELETE <line>`, `INSERT <line>`, the `REPEAT` overload). The data-step core (BY
groups, PDV, declarative/deferred tiers, entry-time checking) is genuinely
coherent and well-specified; the friction is all at those two seams.

**Highest-leverage single change:** fix the float model (Finding 1) — mandate
double precision everywhere. It closes a real spec/code gap, restores
cross-machine reproducibility, and is the finding most likely to bite a real user
with silently wrong numbers. Findings 2 and 3 are the next tier (both silent
data-integrity issues of the same family as #50–#52).

**Voice conflict worth naming:** Wozniak's instinct ("match the hardware, it's
native") is exactly what produced the platform-dependent float — and for a *data*
tool, Kleppmann's reproducibility concern should win. That tension is the root of
Finding 1.
