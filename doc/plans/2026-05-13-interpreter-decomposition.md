# Interpreter Monolith Decomposition Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce `src/sdata-interpreter.adb` from 2,267 lines to ~850 by extracting nine large procedure bodies into Ada subunit files.

**Architecture:** Ada's `separate` (subunit) mechanism lets a procedure body live in its own `.adb` file while retaining full access to all names declared in the parent package body — including package-level state variables, types, and other forward-declared procedures. The parent body keeps a one-line `is separate;` stub. No new package specs are needed, no public API changes, and the GPR file (`sdata.gpr` uses `src/**` glob) picks up the new files automatically.

**Tech Stack:** Ada 2012, GNAT/gprbuild, Alire. Build with `alr build`; test with `make check` (131 tests must pass after every task).

---

## File Structure

**Modified:**
- `src/sdata-interpreter.adb` — nine procedure bodies replaced with `is separate;` stubs; two helper procedures (`Execute_Array_Assignment`, `Coerce_For_Scalar`) removed from top-level and their forward declarations deleted

**Created (one per task):**
- `src/sdata-interpreter-execute_assignment.adb`
- `src/sdata-interpreter-execute_print.adb`
- `src/sdata-interpreter-execute_control_flow.adb`
- `src/sdata-interpreter-execute_metadata.adb`
- `src/sdata-interpreter-execute_declarative.adb`
- `src/sdata-interpreter-execute_io.adb`
- `src/sdata-interpreter-resolve_expr_indices.adb`
- `src/sdata-interpreter-inspect_pdv.adb`
- `src/sdata-interpreter-process_one_record.adb`

**Unchanged:** all `.ads` files, all other `.adb` files, `sdata.gpr`, tests.

---

## Background: Ada subunit syntax

In the parent body, a stub looks like:

```ada
procedure Execute_Print (Stmt : Statement_Access) is separate;
```

The subunit file contains:

```ada
separate (SData.Interpreter)
procedure Execute_Print (Stmt : Statement_Access) is
begin
   -- body here
end Execute_Print;
```

The subunit inherits the `with` clauses of the parent body automatically. It can call any name visible in the parent body's declarative region (other procedures, package-level variables, nested types, etc.).

---

## Task 1: Extract `Execute_Assignment` (with nested helpers)

`Execute_Array_Assignment` (lines 656–737) and `Coerce_For_Scalar` (lines 742–793) are only ever called from `Execute_Assignment` (lines 796–833). Move both into `Execute_Assignment` as nested subprograms, then make `Execute_Assignment` a subunit. This removes three entries from the parent body and their two forward declarations.

**Files:**
- Modify: `src/sdata-interpreter.adb:103–105` (remove two forward declarations)
- Modify: `src/sdata-interpreter.adb:656–833` (remove three procedure bodies; replace `Execute_Assignment` body with stub)
- Create: `src/sdata-interpreter-execute_assignment.adb`

- [ ] **Step 1: Remove the two forward declarations from the parent body**

  In `src/sdata-interpreter.adb`, delete lines 104–105 (the forward declarations for `Execute_Array_Assignment` and `Coerce_For_Scalar`):

  ```ada
     procedure Execute_Array_Assignment (Stmt : Statement_Access; Var_Name : String; Result : Value);
     function  Coerce_For_Scalar       (Var_Name : String; Raw : Value) return Value;
  ```

  Leave line 103 (`procedure Execute_Assignment (Stmt : Statement_Access);`) intact — it is called from `Execute_Statement`.

- [ ] **Step 2: Replace the three procedure bodies in the parent with a single stub**

  Delete lines 656–833 (the full bodies of `Execute_Array_Assignment`, `Coerce_For_Scalar`, and `Execute_Assignment`) and replace with:

  ```ada
     procedure Execute_Assignment (Stmt : Statement_Access) is separate;
  ```

- [ ] **Step 3: Create `src/sdata-interpreter-execute_assignment.adb`**

  The file must begin with `separate (SData.Interpreter)` and contain `Execute_Assignment` with `Execute_Array_Assignment` and `Coerce_For_Scalar` as nested subprograms inside it:

  ```ada
  separate (SData.Interpreter)
  procedure Execute_Assignment (Stmt : Statement_Access) is

     procedure Execute_Array_Assignment
       (Stmt     : Statement_Access;
        Var_Name : String;
        Result   : Value)
     is
        -- paste body from old lines 660–737 verbatim
     end Execute_Array_Assignment;

     function Coerce_For_Scalar (Var_Name : String; Raw : Value) return Value is
        -- paste body from old lines 742–793 verbatim
     end Coerce_For_Scalar;

  begin
     -- paste Execute_Assignment body from old lines 797–833 verbatim
     -- (the two calls to Execute_Array_Assignment and Coerce_For_Scalar
     --  resolve to the nested subprograms above — no changes needed)
  end Execute_Assignment;
  ```

  Copy the bodies verbatim; no logic changes.

- [ ] **Step 4: Build**

  ```
  alr build
  ```

  Expected: `Success: Build finished successfully`. Zero warnings about `Execute_Array_Assignment` or `Coerce_For_Scalar` being unused.

- [ ] **Step 5: Run tests**

  ```
  make check
  ```

  Expected: `All 131 tests passed.`

- [ ] **Step 6: Commit**

  ```bash
  git add src/sdata-interpreter.adb src/sdata-interpreter-execute_assignment.adb
  git commit -m "refactor: extract Execute_Assignment into interpreter subunit"
  ```

---

## Task 2: Extract `Execute_Print`

`Execute_Print` (lines 836–931 in the original file; adjust for Task 1's edits) handles the PRINT statement including array-range printing.

**Files:**
- Modify: `src/sdata-interpreter.adb` — replace `Execute_Print` body with stub
- Create: `src/sdata-interpreter-execute_print.adb`

- [ ] **Step 1: Replace `Execute_Print` body with stub in parent**

  Find the body that starts with:
  ```ada
     procedure Execute_Print (Stmt : Statement_Access) is
     begin
  ```
  and ends with `end Execute_Print;`. Replace the entire body with:
  ```ada
     procedure Execute_Print (Stmt : Statement_Access) is separate;
  ```

- [ ] **Step 2: Create `src/sdata-interpreter-execute_print.adb`**

  ```ada
  separate (SData.Interpreter)
  procedure Execute_Print (Stmt : Statement_Access) is
  begin
     -- paste Execute_Print body verbatim
  end Execute_Print;
  ```

- [ ] **Step 3: Build**

  ```
  alr build
  ```

  Expected: `Success: Build finished successfully`.

- [ ] **Step 4: Run tests**

  ```
  make check
  ```

  Expected: `All 131 tests passed.`

- [ ] **Step 5: Commit**

  ```bash
  git add src/sdata-interpreter.adb src/sdata-interpreter-execute_print.adb
  git commit -m "refactor: extract Execute_Print into interpreter subunit"
  ```

---

## Task 3: Extract `Execute_Control_Flow`

`Execute_Control_Flow` handles IF/WHILE/FOR/REPEAT_UNTIL/SELECT. It calls `Execute_List` (which remains in the parent body — the forward declaration keeps it visible).

**Files:**
- Modify: `src/sdata-interpreter.adb` — replace `Execute_Control_Flow` body with stub
- Create: `src/sdata-interpreter-execute_control_flow.adb`

- [ ] **Step 1: Replace `Execute_Control_Flow` body with stub in parent**

  Find the body starting with:
  ```ada
     procedure Execute_Control_Flow (Stmt : Statement_Access; Ctx : in out Step_Context) is
  ```
  Replace the full body (ends `end Execute_Control_Flow;`) with:
  ```ada
     procedure Execute_Control_Flow (Stmt : Statement_Access; Ctx : in out Step_Context) is separate;
  ```

- [ ] **Step 2: Create `src/sdata-interpreter-execute_control_flow.adb`**

  ```ada
  separate (SData.Interpreter)
  procedure Execute_Control_Flow (Stmt : Statement_Access; Ctx : in out Step_Context) is
  begin
     -- paste Execute_Control_Flow body verbatim
  end Execute_Control_Flow;
  ```

- [ ] **Step 3: Build**

  ```
  alr build
  ```

  Expected: `Success: Build finished successfully`.

- [ ] **Step 4: Run tests**

  ```
  make check
  ```

  Expected: `All 131 tests passed.`

- [ ] **Step 5: Commit**

  ```bash
  git add src/sdata-interpreter.adb src/sdata-interpreter-execute_control_flow.adb
  git commit -m "refactor: extract Execute_Control_Flow into interpreter subunit"
  ```

---

## Task 4: Extract `Execute_Metadata`

`Execute_Metadata` (~258 lines) handles KEEP/DROP/HOLD/UNHOLD/UNSET/RENAME/ARRAY/DIM/NAMES/LIST/DISPLAY. It calls `Expand_Range`, `Expand_Colon_Names`, `List_Virtual_Arrays`, `Undefine_Virtual_Array`, `Define_Array`, `Dim_Array`, `Get_Array_Bounds` — all still in the parent body or their respective packages.

**Files:**
- Modify: `src/sdata-interpreter.adb` — replace `Execute_Metadata` body with stub
- Create: `src/sdata-interpreter-execute_metadata.adb`

- [ ] **Step 1: Replace `Execute_Metadata` body with stub in parent**

  Find the body starting with:
  ```ada
     procedure Execute_Metadata (Stmt : Statement_Access) is
  ```
  Replace the full body (ends `end Execute_Metadata;`) with:
  ```ada
     procedure Execute_Metadata (Stmt : Statement_Access) is separate;
  ```

- [ ] **Step 2: Create `src/sdata-interpreter-execute_metadata.adb`**

  ```ada
  separate (SData.Interpreter)
  procedure Execute_Metadata (Stmt : Statement_Access) is
  begin
     -- paste Execute_Metadata body verbatim
  end Execute_Metadata;
  ```

- [ ] **Step 3: Build**

  ```
  alr build
  ```

  Expected: `Success: Build finished successfully`.

- [ ] **Step 4: Run tests**

  ```
  make check
  ```

  Expected: `All 131 tests passed.`

- [ ] **Step 5: Commit**

  ```bash
  git add src/sdata-interpreter.adb src/sdata-interpreter-execute_metadata.adb
  git commit -m "refactor: extract Execute_Metadata into interpreter subunit"
  ```

---

## Task 5: Extract `Execute_Declarative`

`Execute_Declarative` (~295 lines) handles USE/SAVE/SORT/BY/REPEAT/SELECT_FILTER/DIGITS/RSEED/NEW/OPTIONS. It contains a nested helper `Dlm_To_Str`. It calls `Full_Path`, `Execute` (for NEW), `Rebuild_Filter_Map`, and various `SData.Config.Runtime` accessors — all visible from a subunit.

**Files:**
- Modify: `src/sdata-interpreter.adb` — replace `Execute_Declarative` body with stub
- Create: `src/sdata-interpreter-execute_declarative.adb`

- [ ] **Step 1: Replace `Execute_Declarative` body with stub in parent**

  Find the body starting with:
  ```ada
     procedure Execute_Declarative (Stmt : Statement_Access) is

        --  Convert a DLM string ...
        function Dlm_To_Str (S : String) return String is
  ```
  Replace the entire body (ends `end Execute_Declarative;`) with:
  ```ada
     procedure Execute_Declarative (Stmt : Statement_Access) is separate;
  ```

- [ ] **Step 2: Create `src/sdata-interpreter-execute_declarative.adb`**

  The nested `Dlm_To_Str` function travels with the body naturally:

  ```ada
  separate (SData.Interpreter)
  procedure Execute_Declarative (Stmt : Statement_Access) is

     function Dlm_To_Str (S : String) return String is
        -- paste Dlm_To_Str body verbatim
     end Dlm_To_Str;

  begin
     -- paste Execute_Declarative case body verbatim
  end Execute_Declarative;
  ```

- [ ] **Step 3: Build**

  ```
  alr build
  ```

  Expected: `Success: Build finished successfully`.

- [ ] **Step 4: Run tests**

  ```
  make check
  ```

  Expected: `All 131 tests passed.`

- [ ] **Step 5: Commit**

  ```bash
  git add src/sdata-interpreter.adb src/sdata-interpreter-execute_declarative.adb
  git commit -m "refactor: extract Execute_Declarative into interpreter subunit"
  ```

---

## Task 6: Extract `Execute_IO`

`Execute_IO` (~90 lines) handles SUBMIT/SYSTEM/OUTPUT/FPATH. It calls `Full_Path` and `Execute` — both still in the parent body and visible from the subunit.

**Files:**
- Modify: `src/sdata-interpreter.adb` — replace `Execute_IO` body with stub
- Create: `src/sdata-interpreter-execute_io.adb`

- [ ] **Step 1: Replace `Execute_IO` body with stub in parent**

  Find the body starting with:
  ```ada
     procedure Execute_IO (Stmt : Statement_Access) is
  ```
  Replace the full body (ends `end Execute_IO;`) with:
  ```ada
     procedure Execute_IO (Stmt : Statement_Access) is separate;
  ```

- [ ] **Step 2: Create `src/sdata-interpreter-execute_io.adb`**

  ```ada
  separate (SData.Interpreter)
  procedure Execute_IO (Stmt : Statement_Access) is
  begin
     -- paste Execute_IO body verbatim
  end Execute_IO;
  ```

- [ ] **Step 3: Build**

  ```
  alr build
  ```

  Expected: `Success: Build finished successfully`.

- [ ] **Step 4: Run tests**

  ```
  make check
  ```

  Expected: `All 131 tests passed.`

- [ ] **Step 5: Commit**

  ```bash
  git add src/sdata-interpreter.adb src/sdata-interpreter-execute_io.adb
  git commit -m "refactor: extract Execute_IO into interpreter subunit"
  ```

---

## Task 7: Extract `Resolve_Expr_Indices`

`Resolve_Expr_Indices` (~100 lines) walks an AST to cache PDV slot indices. It contains two nested procedures (`Resolve_Expr` and `Resolve_Stmt_List`) and one nested procedure that mutually recurses with the outer (`Resolve_Stmt`). The nesting travels with the body — no restructuring needed.

**Files:**
- Modify: `src/sdata-interpreter.adb` — replace `Resolve_Expr_Indices` body with stub
- Create: `src/sdata-interpreter-resolve_expr_indices.adb`

- [ ] **Step 1: Replace `Resolve_Expr_Indices` body with stub in parent**

  Find the body starting with:
  ```ada
     procedure Resolve_Expr_Indices (Start, Boundary : Statement_Access) is
  ```
  Replace the full body (ends `end Resolve_Expr_Indices;`) with:
  ```ada
     procedure Resolve_Expr_Indices (Start, Boundary : Statement_Access) is separate;
  ```

- [ ] **Step 2: Create `src/sdata-interpreter-resolve_expr_indices.adb`**

  ```ada
  separate (SData.Interpreter)
  procedure Resolve_Expr_Indices (Start, Boundary : Statement_Access) is

     procedure Resolve_Expr (Expr : Expression_Access);

     procedure Resolve_Expr_List (List : Expression_List) is
        -- paste verbatim
     end Resolve_Expr_List;

     procedure Resolve_Expr (Expr : Expression_Access) is
        -- paste verbatim
     end Resolve_Expr;

     procedure Resolve_Stmt_List (Stmt  : Statement_Access;
                                   Bound : Statement_Access);

     procedure Resolve_Stmt (S : Statement_Access) is
        -- paste verbatim
     end Resolve_Stmt;

     procedure Resolve_Stmt_List (Stmt  : Statement_Access;
                                   Bound : Statement_Access) is
        -- paste verbatim
     end Resolve_Stmt_List;

  begin
     Resolve_Stmt_List (Start, Boundary);
  end Resolve_Expr_Indices;
  ```

- [ ] **Step 3: Build**

  ```
  alr build
  ```

  Expected: `Success: Build finished successfully`.

- [ ] **Step 4: Run tests**

  ```
  make check
  ```

  Expected: `All 131 tests passed.`

- [ ] **Step 5: Commit**

  ```bash
  git add src/sdata-interpreter.adb src/sdata-interpreter-resolve_expr_indices.adb
  git commit -m "refactor: extract Resolve_Expr_Indices into interpreter subunit"
  ```

---

## Task 8: Extract `Inspect_PDV`

`Inspect_PDV` (~133 lines) is the interactive debugger for BREAK. It contains a nested procedure `Load_Inspect_Record`. It calls `Execute_Statement` (forward-declared in parent, visible from subunit).

**Files:**
- Modify: `src/sdata-interpreter.adb` — replace `Inspect_PDV` body with stub
- Create: `src/sdata-interpreter-inspect_pdv.adb`

- [ ] **Step 1: Replace `Inspect_PDV` body with stub in parent**

  Find the body starting with:
  ```ada
     procedure Inspect_PDV
       (Logical_I     :        Positive;
        Logical_Count :        Natural;
        Action        :    out Step_Action)
     is
  ```
  Replace the full body (ends `end Inspect_PDV;`) with:
  ```ada
     procedure Inspect_PDV
       (Logical_I     :        Positive;
        Logical_Count :        Natural;
        Action        :    out Step_Action)
     is separate;
  ```

- [ ] **Step 2: Create `src/sdata-interpreter-inspect_pdv.adb`**

  ```ada
  separate (SData.Interpreter)
  procedure Inspect_PDV
    (Logical_I     :        Positive;
     Logical_Count :        Natural;
     Action        :    out Step_Action)
  is
     Inspect_I  : Positive := Logical_I;
     Saved_Phys : constant Positive :=
        SData.Table.Logical_To_Physical (Logical_I);

     procedure Load_Inspect_Record (L : Positive) is
        -- paste verbatim
     end Load_Inspect_Record;

  begin
     -- paste Inspect_PDV body verbatim
  end Inspect_PDV;
  ```

- [ ] **Step 3: Build**

  ```
  alr build
  ```

  Expected: `Success: Build finished successfully`.

- [ ] **Step 4: Run tests**

  ```
  make check
  ```

  Expected: `All 131 tests passed.`

- [ ] **Step 5: Commit**

  ```bash
  git add src/sdata-interpreter.adb src/sdata-interpreter-inspect_pdv.adb
  git commit -m "refactor: extract Inspect_PDV into interpreter subunit"
  ```

---

## Task 9: Extract `Process_One_Record`

`Process_One_Record` (~131 lines) is the per-record PDV load/execute/flush cycle. It calls `Group_Flags`, `Set_Group_Boundary`, `Execute_Statement`, `Inspect_PDV`, and `Flush_PDV_To_Output` — all forward-declared in the parent body and visible from the subunit.

**Files:**
- Modify: `src/sdata-interpreter.adb` — replace `Process_One_Record` body with stub
- Create: `src/sdata-interpreter-process_one_record.adb`

- [ ] **Step 1: Replace `Process_One_Record` body with stub in parent**

  Find the body starting with:
  ```ada
     procedure Process_One_Record (Logical_I        : Positive;
                                    Logical_Count    : Natural;
                                    Start            : Statement_Access;
                                    Boundary         : Statement_Access;
                                    Global_Has_Write : Boolean;
                                    Ctx              : in out Step_Context;
                                    Pause_After      : Boolean := False;
                                    Action           : out Step_Action) is
  ```
  Replace the full body (ends `end Process_One_Record;`) with:
  ```ada
     procedure Process_One_Record (Logical_I        : Positive;
                                    Logical_Count    : Natural;
                                    Start            : Statement_Access;
                                    Boundary         : Statement_Access;
                                    Global_Has_Write : Boolean;
                                    Ctx              : in out Step_Context;
                                    Pause_After      : Boolean := False;
                                    Action           : out Step_Action) is separate;
  ```

- [ ] **Step 2: Create `src/sdata-interpreter-process_one_record.adb`**

  ```ada
  separate (SData.Interpreter)
  procedure Process_One_Record (Logical_I        : Positive;
                                 Logical_Count    : Natural;
                                 Start            : Statement_Access;
                                 Boundary         : Statement_Access;
                                 Global_Has_Write : Boolean;
                                 Ctx              : in out Step_Context;
                                 Pause_After      : Boolean := False;
                                 Action           : out Step_Action) is
     Phys_I : constant Positive := SData.Table.Logical_To_Physical (Logical_I);
     Iter   : Statement_Access;
  begin
     -- paste Process_One_Record body verbatim
  end Process_One_Record;
  ```

- [ ] **Step 3: Build**

  ```
  alr build
  ```

  Expected: `Success: Build finished successfully`.

- [ ] **Step 4: Run tests**

  ```
  make check
  ```

  Expected: `All 131 tests passed.`

- [ ] **Step 5: Commit**

  ```bash
  git add src/sdata-interpreter.adb src/sdata-interpreter-process_one_record.adb
  git commit -m "refactor: extract Process_One_Record into interpreter subunit"
  ```

---

## Task 10: Update documentation

- [ ] **Step 1: Verify final line count**

  ```bash
  wc -l src/sdata-interpreter.adb
  ```

  Expected: under 900 lines.

- [ ] **Step 2: Update `doc/architecture.md` Package Map**

  In `doc/architecture.md`, expand the `SData.System` line in the package map to list the new subunits:

  ```
  SData.Interpreter      statement executor and data step engine
    ├── (subunits)       execute_assignment, execute_print,
    │                    execute_control_flow, execute_metadata,
    │                    execute_declarative, execute_io,
    │                    resolve_expr_indices, inspect_pdv,
    │                    process_one_record
  ```

- [ ] **Step 3: Add an annotation to `doc/SOFTWARE_STANDARDS_REVIEW.md`**

  Add a new annotation line (following the existing format) noting:
  - Date, version, what was done
  - §1 score increase (interpreter monolith resolved)
  - §2 score increase (cognitive load reduction)
  - §4 score increase (change resilience: adding a command now touches one focused subunit)
  - Updated total

- [ ] **Step 4: Commit**

  ```bash
  git add doc/architecture.md doc/SOFTWARE_STANDARDS_REVIEW.md
  git commit -m "doc: update architecture and standards review for interpreter decomposition"
  ```
