# Design: Inf / -Inf Support

**Date:** 2026-05-06
**Status:** Approved

---

## 1. Scope

Inf and -Inf are IEEE 754 concepts that apply to floating-point numbers only.
`Val_Numeric` (Ada `Float`) is IEEE 754 and already produces Inf internally from
arithmetic overflow; this feature makes Inf a first-class, visible value.
`Val_Integer` (Ada `Integer`) has no hardware representation of infinity and is
not affected.

---

## 2. Sources of Inf

| Expression | Result |
|---|---|
| `Float'Last * 2.0` (or any overflow) | +Inf (`Val_Numeric`) |
| `-Float'Last * 2.0` | -Inf (`Val_Numeric`) |
| `nonzero / 0.0` with `OPTIONS IEEE_DIVIDE` | ±Inf (`Val_Numeric`) |
| `0.0 / 0.0` (any mode) | NaN → see §3 |

Without `OPTIONS IEEE_DIVIDE`, all float division by zero raises `Script_Error`
(current behaviour, unchanged).

---

## 3. NaN Handling (Option C)

NaN arises from Inf arithmetic such as `Inf - Inf` or `0.0 * Inf`. It is not a
first-class value. NaN results route through the existing `Handle_Domain_Error`
mechanism:

- **Default**: `Script_Error` ("Result is not a number (NaN)")
- **With `--ignore-math-errors`**: `Val_Missing`

This is consistent with how existing domain errors (e.g. `SQRT(-1)`) are handled.

---

## 4. Float Division by Zero

| Condition | `nonzero / 0.0` | `0.0 / 0.0` |
|---|---|---|
| Default (no option) | `Script_Error` | `Script_Error` |
| `OPTIONS IEEE_DIVIDE` | ±Inf | NaN → `Handle_Domain_Error` (§3) |

`OPTIONS IEEE_DIVIDE` is a persistent interpreter-level setting, cleared by `NEW`.

---

## 5. Inf → Integer Conversion

Assigning Inf/-Inf to an integer variable, or passing Inf/-Inf to a function
that returns an integer result (`FLOOR`, `CEIL`, `ROUND`, `INT`, `TRUNC`, etc.),
routes through `Handle_Domain_Error`:

- **Default**: `Script_Error` ("Cannot convert Inf to integer")
- **With `--ignore-math-errors`**: `Val_Missing`

This matches the treatment of NaN and is consistent with integer overflow
(which already raises `Script_Error`).

---

## 6. Aggregate Functions

Aggregate functions (`SUM`, `MEAN`, `MIN`, `MAX`, `STDEV`, etc.) currently skip
`Val_Missing` inputs. With Inf as a first-class `Val_Numeric`, IEEE propagation
applies:

| Expression | Result |
|---|---|
| `SUM({1, 2, Inf})` | Inf |
| `MIN({x, Inf})` | x |
| `MAX({x, -Inf})` | x |
| `SUM({Inf, -Inf})` | NaN → `Handle_Domain_Error` (§3) |
| `MEAN({Inf, 1})` | Inf |

There is no special Inf-skipping logic; Inf flows through IEEE arithmetic
naturally, and NaN is the only error surface.

---

## 7. Detection Function

A new built-in function:

```
INF(x)
```

- Returns `1` if `x` is +Inf or -Inf; `0` otherwise.
- Returns `0` for `Val_Missing` (Missing is not Inf).
- Returns `0` for finite numeric values and strings.
- To test specifically for +Inf or -Inf, combine `INF()` with a sign comparison:
  - `INF(x) AND x > 0` — true only for +Inf
  - `INF(x) AND x < 0` — true only for -Inf
- `NOT INF(x)` serves the role of `FINITE()` for non-missing values.

---

## 8. Display and I/O

### PRINT output

| Value | Displayed as |
|---|---|
| +Inf | `Inf` |
| -Inf | `-Inf` |

### CSV / ODF / OOXML output

- **CSV**: Inf cells are written as the literal strings `Inf` or `-Inf`.
- **ODF / OOXML**: There is no standard numeric cell type for infinity in either
  format. Inf cells are written as *string-type* cells containing `Inf` or `-Inf`.
  This preserves the value visibly and allows round-trip recognition on re-read.

### CSV / ODF / OOXML input

The parser recognises the following spellings (case-insensitive) as `Val_Numeric`
Inf, regardless of whether the source cell is typed as string or numeric:

| Accepted spellings |
|---|
| `Inf`, `+Inf`, `-Inf` |
| `Infinity`, `+Infinity`, `-Infinity` |

Any other non-numeric cell value that is not a recognised Missing sentinel
continues to be treated as `Val_String` or `Val_Missing` per existing rules.

---

## 9. MISSING() Interaction

`MISSING(x)` returns `0` when `x` is Inf or -Inf. Inf is a numeric value, not a
missing value. Scripts that need to handle both conditions must check both:

```
IF MISSING(x) OR INF(x) THEN ...
```

---

## 10. SORT and BY Groups

- **SORT**: IEEE ordering applies — `-Inf < all finite values < Inf`. Rows with
  Inf in the sort key sort last (ascending), rows with -Inf sort first.
- **BY groups**: Inf == Inf under IEEE 754 equality, so rows with Inf in the BY
  variable form a single group. -Inf rows form a separate group.

---

## 11. Implementation Touchpoints

| Area | Change |
|---|---|
| `SData.Config` | Add `IEEE_Divide : Boolean := False` |
| `SData.Interpreter` | Handle `OPTIONS IEEE_DIVIDE` |
| `SData.Evaluator` | Float division by zero: branch on `IEEE_Divide`; detect NaN post-op; Inf→int via `Handle_Domain_Error` |
| `SData.Values` | `Image` function: emit `Inf` / `-Inf` for infinite `Val_Numeric` |
| `SData.File_IO` | CSV/ODF/OOXML write: emit `Inf`/`-Inf`; read: recognise Inf spellings |
| `SData.Statistics` | Aggregate functions: propagate Inf via IEEE; detect NaN result |
| `SData.Evaluator` (built-ins) | Add `INF()` function; integer-returning functions: check for Inf input |
| `SData.Help` | Add `INF` topic; document `OPTIONS IEEE_DIVIDE` |
| Tests | Unit tests for each source of Inf, NaN handling, I/O round-trip, aggregates |
