# Design: LBOUND and HBOUND array-bound functions

**Date:** 2026-05-18  
**Status:** Approved

## Summary

Add `HBOUND` as a SAS-compatible alias for the existing `UBOUND` function, and add
full documentation for all three array-bound functions (`LBOUND`, `UBOUND`, `HBOUND`)
in the HELP system and man page (both were absent despite the functions being
operational).

## Background

`LBOUND(a)` and `UBOUND(a)` already exist and work correctly.  They accept an array
name as a bare identifier (via `Is_Identifier_Ref_Function`), look up the array's
`Start_Index` / `End_Index` in `Array_Symbols`, and return the bound as an integer.
Both support virtual arrays (ARRAY command) and real arrays (DIM command).

SAS uses `LBOUND` and `HBOUND` ("H" for high) for the same pair of operations.
`HBOUND` is not currently registered; `UBOUND` is not SAS-compatible by name.
HELP entries and man-page coverage are entirely absent for all three.

## Approach

Alias pattern (Option A): register `HBOUND` pointing to the existing `Handle_Ubound`
handler, following the same convention used for `LOGE`/`LN`, `LAGC$`/`LAG`, etc.
`UBOUND` is retained for backward compatibility.

## Detailed Changes

### 1. `src/sdata-evaluator.adb`

Add `"HBOUND"` to the `Is_Identifier_Ref_Function` membership test alongside
`"LBOUND"` and `"UBOUND"`:

```ada
return U in "LAG" | "LAGC$" | "NEXT" | "NEXTC$" | "OBS" | "OBSC$"
          | "LBOUND" | "UBOUND" | "HBOUND";
```

### 2. `src/sdata-evaluator-misc_fns.adb`

Add one line in the `begin Register;` elaboration block, immediately after the
`UBOUND` registration:

```ada
Dispatch_Table.Insert ("HBOUND", Handle_Ubound'Access);
```

### 3. `src/sdata-help.adb`

**3a. Key constants** — add alongside the existing block:

```ada
K_LBOUND  : aliased constant String := "LBOUND";
K_UBOUND  : aliased constant String := "UBOUND";
K_HBOUND  : aliased constant String := "HBOUND";
```

**3b. Help procedures** — add a new `-- Array functions` section:

```ada
procedure Help_LBOUND is
begin
   Put_Line ("Function: LBOUND(arrayname)");
   Put_Line ("Returns the lower bound (first valid subscript) of the named array.");
   Put_Line ("Works for both virtual arrays (ARRAY) and real arrays (DIM).");
   Put_Line ("Returns missing if the array does not exist.");
   Put_Line ("The array name may be given unquoted: LBOUND(A) is equivalent to LBOUND(""A"").");
   Put_Line ("See also: UBOUND, HBOUND");
end Help_LBOUND;

procedure Help_UBOUND is
begin
   Put_Line ("Function: UBOUND(arrayname) / HBOUND(arrayname)");
   Put_Line ("Returns the upper bound (last valid subscript) of the named array.");
   Put_Line ("HBOUND is the SAS-compatible spelling; UBOUND is retained for compatibility.");
   Put_Line ("Works for both virtual arrays (ARRAY) and real arrays (DIM).");
   Put_Line ("Returns missing if the array does not exist.");
   Put_Line ("The array name may be given unquoted: UBOUND(A) is equivalent to UBOUND(""A"").");
   Put_Line ("See also: LBOUND");
end Help_UBOUND;
```

**3c. Help_Table entries** — add in a new `-- Array functions` comment block
(place near the record-navigation block for logical grouping):

```ada
-- Array functions
(K_LBOUND'Access,  Help_LBOUND'Access,  N, F),
(K_UBOUND'Access,  Help_UBOUND'Access,  N, F),
(K_HBOUND'Access,  Help_UBOUND'Access,  N, N),   --  SAS alias
```

**3d. Help_Index** — update the Arrays line:

```ada
Put_Line ("  Arrays:      LBOUND, UBOUND, HBOUND");
```

### 4. `man/man1/sdata.1`

Add a new `.SS Arrays` subsection under `.SH FUNCTIONS`, placed after `.SS Special`
and before `.SS Statistical distributions`:

```nroff
.SS Arrays
.BR LBOUND ( arrayname )
\(em lower bound (first valid subscript) of the named array.
.br
.BR UBOUND ( arrayname )\ /\ HBOUND ( arrayname )
\(em upper bound (last valid subscript) of the named array.
.B HBOUND
is the SAS\-compatible spelling;
.B UBOUND
is retained for compatibility.
.br
Both functions accept the array name as a bare identifier or as a string literal.
Returns missing if the array does not exist.
```

### 5. Tests

**5a. `tests/sdata_unit_test.adb`** — add alongside the existing E-12/E-13 checks:

```ada
Check ("E-14 HBOUND is identifier-ref", Is_Identifier_Ref_Function ("HBOUND"), True);
```

**5b. `tests/new_functions_test.cmd`** — extend the LBOUND/UBOUND block to also
exercise HBOUND:

```
PRINT HBOUND(A)   -- same as UBOUND(A): expects 7
PRINT HBOUND(B)   -- same as UBOUND(B): expects 5
```

**5c. `tests/expected/new_functions_test.out`** — append two lines after the
existing UBOUND results:

```
7
5
```

**5d. `tests/expected/help_index.out`** — update the Arrays line:

```
  Arrays:      LBOUND, UBOUND, HBOUND
```

## Behaviour Specification

| Call | Array defined as | Returns |
|---|---|---|
| `LBOUND(A)` | `DIM A(3 TO 7)` | 3 |
| `UBOUND(A)` | `DIM A(3 TO 7)` | 7 |
| `HBOUND(A)` | `DIM A(3 TO 7)` | 7 |
| `LBOUND(V)` | `ARRAY V X Y Z` | 1 |
| `HBOUND(V)` | `ARRAY V X Y Z` | 3 |
| `LBOUND(X)` | (not defined) | missing |
| `HBOUND(X)` | (not defined) | missing |

## Out of Scope

- Multi-dimensional arrays (sdata has none)
- The `dim` argument form `HBOUND(a, n)` present in SAS (not applicable here)
- Renaming `UBOUND` to `HBOUND` (would break existing scripts)
