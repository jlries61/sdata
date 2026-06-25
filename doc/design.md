# Data Command Interpreter Specification

## 1. INTRODUCTION

### 1.1 Overview

This document specifies a command interpreter modeled on Systat BASIC that operates on a two-dimensional table residing either in memory or an external file. The interpreter shall be written in Ada and compilable with any recent version of GNU GNAT on any platform upon which it runs. The language shall be entirely case insensitive.

Key Requirements:

- No hard memory or dimensional constraints.
- No limits on nesting of *FOR* loops or other structures.
- Can run as stand-alone text-based application or embedded in a larger system.
- External libraries must be freely available and compatible with proprietary software.
- Code must be modular, readable, maintainable, and well-documented.
- No copyrighted code may be copied into the generated code base.

### 1.2 BW BASIC Compatibility

Unless otherwise specified, the commands and functions listed shall be implemented as specified in the documentation for Bywater BASIC 3.20, but deviations are allowed when necessary. Bywater commands and functions not listed in this document shall not be supported.

## 2. DATA MODEL

### 2.1 The Internal Table

The interpreter operates on a two-dimensional table containing any number of rows (records) and columns (variables). The table may reside in memory if small enough, or in an external file with an in-memory cache.

Memory Management:

- Maximum in-memory size: set by *-m* command line option or *OPTIONS MAXINTAB*.
- External file storage: used when table exceeds maximum in-memory size.
- Cache size: equal to maximum in-memory size, but never less than the size of a single row.
- Implementation details: format and properties of external file and cache are implementation-defined.

**Column Ordering:** Permanent variables (including arrays) shall appear as columns in the internal table in the order in which they were created.

### 2.2 Data Types

Three data types shall be supported:

#### Floating Point Numeric

Platform-dependent precision:

- 128-bit architectures: IEEE 754 quadruple precision (128-bit).
- 64-bit architectures: IEEE 754 double precision (64-bit).
- 32-bit architectures: IEEE 754 single precision (32-bit).
- Architectures with word size \< 32 bits: unsupported.

#### Integer

32-bit signed integer.

#### Character

- Variable-length character strings.
- Maximum length: specifiable via *–clen* command line argument (default: 256 characters).
- Truncation: If a string exceeds maximum length, a warning shall be issued and the string truncated from the right, keeping only the leftmost characters that fit.

### 2.3 Type Conversion and Mixed Mode Arithmetic

Conversion Rules:

- If an operation uses both floating point and integer values, integer values shall first be converted to their floating point equivalents.
- If an integer value is written to a floating point variable, it shall be converted to its floating point equivalent.
- If a floating point value is written to an integer variable, the fractional part shall be truncated (rounded toward zero).
- Arithmetic operations involving character values shall be unsupported.

### 2.4 Overflow Handling

**Integer Overflow:** Operations producing values outside the range -2,147,483,648 to 2,147,483,647 shall fail with an error message.

**Floating Point Overflow:** Floating point operations that would produce values exceeding the representable range shall likewise fail with an error message.

**Note:** Future versions may support special missing value codes for IEEE 754 infinity and NaN values.

### 2.5 Missing Values

Representation:

- Numeric missing value: unquoted period (*.*).
- Character missing value: empty string (*""*).

Propagation Rules:

- Operations on missing values shall result in missing values.
- Null strings (*""*) in string operations shall be taken literally.
- If no non-missing arguments are passed to an aggregate function, a missing value shall be returned.
- Aggregate functions shalfunctionl ignore missing values when making computations.

Error Conditions (not missing values):

- Division by zero shall terminate the current running program with an error message.
- Attempted operations that reference non-existent array elements shall fail with an error message.
- Mathematical functions receiving invalid arguments (e.g., non-positive argument to *LOG*) shall fail with an error message.

## 3. VARIABLES AND ARRAYS

### 3.1 Variable Types

Two categories of variables are supported:

#### Permanent Variables

- Stored as columns in the internal table.
- Written to output datasets when *SAVE* command is executed.
- Unless a *HOLD* statement is in effect, permanent variables not appearing in the input dataset shall be reset to missing each time a new record is read (if *USE* statement in effect) or created (if *REPEAT* statement in effect).
- If *HOLD* statement is in effect, affected variables not in the input dataset retain their values until explicitly changed.
- If *KEEP* statement is executed, all permanent variables not listed in it shall be deleted at the last step of the next *RUN* statement.

#### Temporary Variables

- Single values (numeric or character) not saved when internal table is written to external file.
- Retained for the duration of the session until explicitly deleted (*DROP* statement) or implicitly deleted (*NEW* statement).
- Always retain their values until/unless explicitly changed.
- Maximum memory: set via command line *-t* option or *OPTIONS MAXTEMPMEM.*
- If maximum would be exceeded by creating a new variable/array or increasing array size, the statement shall fail with an error message.

### 3.2 Variable Names and Syntax

Base Variable Names:

- 1 to 64 characters.
- May contain: uppercase letters, numerals, underscores.
- Case insensitive.

Type Indicators:

- Character variables: base name + *\$* suffix.
- Integer variables: base name + *%* suffix.
- Floating point variables: base name only (no suffix).

Array Elements:

- Format: *arrayname(subscript).*
- Example: *TEMP(5)*, *NAME\$(3)*

Examples:

- *LENGTH* - Scalar numeric variable.
- *NAME\$* - Scalar character variable.
- *COUNT%* - Scalar integer variable.
- *FINGER_LEN(1)* - Member of a numeric array.
- *ALIAS\$(2)* - Member of a character array.

Type Compatibility:

- The type indicated by a name's suffix is fixed: a *\$* name is always character, a *%* name is always integer, and an unsuffixed name is always floating point.
- Numeric kinds interconvert on assignment (an integer value assigned to a floating-point name is promoted; a floating-point value assigned to a *%* name is truncated), but character and numeric values never interconvert.
- Assigning a character value to a numeric name (or a numeric value to a *\$* name) is therefore always an error. For example, *SET NAME = "foo"* fails because *NAME* is numeric; the character form is *SET NAME\$ = "foo"*.
- When the right-hand side of a *LET* or *SET* is a literal, this conflict is detected immediately, as the statement is entered, rather than being deferred to the next *RUN*. (When the right-hand side is a variable or expression, whose kind is not known until the data step executes, the check remains deferred to *RUN*.)

Quoted Identifiers (Backtick Form):

- A column or variable whose name collides with a reserved keyword, or contains spaces or dots, can be referenced by enclosing it in backticks (`` ` ``).
- The backtick form is accepted wherever a bare identifier is accepted (expressions, *LET*/*SET*, *PRINT*, *KEEP*/*DROP*, *RENAME*, *BY*, *ARRAY*/*DIM*, *SORT*, per-dataset *KEEP=*/*DROP=*/*RENAME=*/*IN=*).
- The identifier between backticks is taken verbatim and upper-cased on lookup, exactly like a bare identifier.
- Examples: `` `AS` `` (column named AS), `` `col with spaces` `` (column with embedded spaces).
- Empty backticks (` `` `) and unterminated or newline-containing backtick sequences are lexical errors.
- *NAMES* output and error messages show the bare name without backticks; the backtick form is an input notation only.
- When *USE* loads a dataset with column names matching reserved keywords, an advisory warning is emitted showing the backtick form to use. This warning is controlled by *OPTIONS WARNRESERVED* (default: YES).

### 3.3 Arrays

Three types of arrays are supported:

#### Permanent Arrays

- Elements are columns in the internal table
- Written to output datasets via *SAVE* command
- When written, one column created per element in consecutive columns
- Column names: array name + subscript in parentheses (e.g., *DATA(1)*, *DATA(2)*)
- Columns appear in numeric order of subscripts

#### Temporary Arrays

- Elements not written to output datasets
- Remain in memory until deleted or redefined
- Subject to temporary variable memory limits

#### Virtual Arrays

- Consist of one or more existing scalar variables
- Constituent variables ordered as specified in *ARRAY* statement
- All elements must be same type as specified by array name
- When creating a virtual array with *ARRAY* command, all constituent variables must already exist; otherwise statement fails with error
- May consist of permanent variables, temporary variables, or both
- Element names are aliases for constituent variable names

Array Subscripting:

- **Default:** 1-based (first element = subscript 1, second = subscript 2, etc.) .
- **Custom subscripts:** Supported for *DIM* arrays only (e.g., *DIM MONTH(0 TO 11)*, *DIM YEAR(2000 TO 2030)*).
- **Virtual arrays:** Custom subscripts not supported

Multiple Element Reference:

- Comma-delimited list of subscripts: *ARRAY(1,3,5).*
- Subscript ranges: *ARRAY(2:5).*
- Elements must already exist.

Interchangeability: Except as specified elsewhere, arrays of the three types shall be fully interchangeable in all operations.

**Error Condition:** References to non-existent array elements cause the current program to fail with an error message.

### 3.4 Variable Lifecycle

#### Creation

Variables and arrays may be created by:

- **USE command:**

  - Columns of input dataset added as permanent variables/arrays.
  - If variables/arrays with same names already exist, they are replaced.
  - If names match existing virtual arrays, those virtual arrays are undefined.

- **LET command:** Creates permanent scalar variables.

- **SET command:** Creates temporary scalar variables.

- DIM command:

  - Creates permanent or temporary arrays.
  - Elements initially filled with missing values.
  - May be modified by subsequent *LET* or *SET* statements.
  - Appending */TEMP* to *DIM* statement creates temporary array.

- **ARRAY command:** Creates virtual arrays from existing variables.

- **Function return values:** Some functions return arrays when referenced in *LET* or *SET* statements.

#### Initialization

Permanent Variables:

- Unless *HOLD* statement is in effect, reset to missing each time new record is read or created.
- If *HOLD* statement is in effect, variables not in input dataset retain values until explicitly changed.
- Variables appearing in input dataset are set to new values as each record is read (*HOLD* has no effect on these).

**Temporary Variables:** - Always retain values until/unless explicitly changed.

#### Deletion

Variables and arrays may be deleted by:

- DROP command:

  - Explicitly deletes specified variables/arrays.
  - If *DROP* lists a variable also in *KEEP* statement, variable is deleted nevertheless (modifies *KEEP* statement).
  - Individual array elements cannot be deleted.

- KEEP statement:

  - When executed, all permanent variables/arrays NOT listed are deleted at last step of next *RUN* statement.
  - If virtual array mentioned in *KEEP*, all constituent variables are retained.
  - If virtual array mentioned in *DROP*, all constituent variables are deleted along with virtual array definition.

- **Virtual array operations:** May be redefined or deleted without affecting constituent variables using *ARRAY* statement.

### 3.5 Variable Modification

#### Redefinition Rules

- Existing scalar variables and array elements may be redefined by *LET* or *SET* statements.
- **Permanent → Temporary:** If permanent variable/array redefined by *SET*, it becomes temporary.
- **Temporary → Permanent:** If temporary variable/array redefined by LET, it becomes permanent.
- **Temporary → Permanent via KEEP:** Listing temporary variable/array in *KEEP* statement makes it permanent.
- Existing arrays may not be redefined as scalar variables unless first deleted.
- Existing scalar variables may not be redefined as arrays unless first deleted.

#### Array Modification Restrictions

- *LET* statement may not modify individual elements of temporary array.
- *SET* statement may not modify individual elements of virtual or permanent array.
- Virtual array may be redefined by new *ARRAY* statement (no effect on constituent variables).
- Virtual array may be replaced by permanent/temporary array using *DIM* (no effect on former constituent variables).

#### Array Resizing

Arrays with numbered elements may be resized with new *DIM* statement:

- **Contraction:** Elements outside new range are deleted.
- **Expansion:** New elements filled with missing values.
- **Mixed (expand one end, contract other):** Both above rules apply.

#### Array Redefinition

Existing array may be redefined by *LET* or *SET* statement that would otherwise create new array. If array is virtual, constituent scalar variables are not modified.

### 3.6 Ranges and Literals

#### Range Notation

Two kinds of range notation are supported:

- Dash Range (table order):

  - Format: *VAR1-VAR5*
  - Includes: Named variables and any between them in the internal table, in table order.
  - Example: *CRIM-LSTAT* (*CRIM* through *LSTAT* in current internal table).

- Colon Range (numeric order):

  - Format: *VAR1:VAR10*
  - Includes: Variables between named ones in numeric order
  - Variable names must end with one or more numerals (excluding *\$*, *%*, subscript).
  - Non-existent variables are created if applicable (not needed for *DROP* statement).
  - Example: *MONTHPAY1:MONTHPAY60* (*MONTHPAY1* through *MONTHPAY60* in numeric order).

Array Element Ranges:

- Format: *ARRAY(start:end).*
- Example: *FINGER_LEN(2:3)* (second and third members).

Usage with LET/SET:

- Ranges may be used to redefine array subsets.
- Size of array defined by expression must equal size of array subset being written.

#### Literals

- Numeric Literals:

  - Base ten only (may change in future versions).
  - May be integers, floating point numbers, or E notation.
  - Missing numeric value: unquoted period (*.*).

- Character Literals:

  - Surrounded by single or double quotes.
  - Missing character value: empty string (*""*).

## 4. FILE I/O

### 4.1 Supported File Formats

Three file formats are supported for data input and output:

#### CSV Files

- Character Sets:

  - Supported: ASCII, UTF-8, UTF-16, plus any other character sets supported by host system.
  - Portable guarantee: Only ASCII, UTF-8, and UTF-16 guaranteed portable between systems.

- Input (USE command):

  - Character set auto-detected by default.
  - Override with *CHARSET* option to correct wrong guesses.
  - Invalid characters for detected/specified charset: operation fails with error message.

- Output (SAVE command):

  - Character set specified by *CHARSET* option.
  - Default: session locale, unless changed with *OPTIONS CHARSET.*
  - Characters not representable in output charset: operation fails with error message.

- Delimiters:

  - Determined by *DLM* flag on *USE* and *SAVE* commands.
  - Default: comma, unless changed by *OPTIONS CSVDLM.*
  - May be more than one character long.

- Quote Handling:

  - Embedded quotes: handled by doubling.
  - Single quotes inside double-quoted string: taken literally.
  - Double quotes inside single-quoted string: taken literally.

- Headers:

  - Governed by *HEADER* option on *USE* and *SAVE* commands (values: *YES* or *NO*).
  - Default: *YES*, unless changed by *OPTIONS HEADER.*
  - Affects spreadsheets same way as CSV.

- Line Endings:

  - Default: standard for operating system.
  - Changed via *OPTIONS TXTFMT*.

- Input (USE):

  - Attempts auto-detection if *OPTIONS TXTFMT = AUTO* (default).

- **Output (SAVE):**

  - Uses current TXTFMT setting.

- Overwrite Behavior:

  - Governed by *OPTIONS SAVEOVERWRT.*
  - Default: overwriting permitted.

#### ODF Spreadsheets

- Input (USE):

  - Multiple sheets: First sheet read unless different sheet specified in brackets after filename.
  - Example: *"multibook.ods\[sheet2\]"* - Empty rows and columns: Completely empty ones are skipped.

- Output (SAVE):

  - If sheet not specified and workbook doesn’t exist: Created with single sheet named “Sheet1”.

  - If workbook exists with single sheet: That sheet overwritten (unless overwriting disabled).

  - If specific sheet specified:

    - Sheet exists: Overwritten (unless disabled).
    - Sheet doesn’t exist: Created.

- Formulas:

  - Evaluated during read process.

  - Computed values used.

  - If formula cannot be evaluated (errors or unsupported functions):

    - Cell treated as missing value.
    - Formulas not supported for internal calculations or output.

- Merged Cells:

  - Unsupported.
  - Attempt to read spreadsheet with merged cells: fails with error message.

- Overwrite Behavior: Same as for CSV.

#### OOXML Spreadsheets

Same behavior as ODF spreadsheets (see above).

**Note:** Support for other formats likely to be added in future versions.

### 4.2 Input Operations

**USE Statement:** Reads dataset into internal table, creating permanent variables from columns.

- Type Detection:

  - First *NSCAN* records examined to determine column types (default *NSCAN* = 20).
  - After type detection, non-numeric values in numeric columns: set to missing value, warning issued.
  - Duplicate column names: Last occurrence wins, warning issued.

- Error Conditions:

  - Non-existent file: fails with error.
  - File without read permission: fails with error.

### 4.3 Output Operations

**SAVE Statement:** Writes internal table to specified dataset.

- Missing Value Representation:

  - CSV files: Consecutive delimiters.
  - Spreadsheets: Empty cell.

- Error Conditions:

  - File without write permission: fails with error.
  - Non-existent target directory: fails with error.
  - Permission verification: Immediately upon statement execution, before actual write.

- **Overwrite Behavior:** Controlled by *OPTIONS SAVEOVERWRT* (default: permitted).

### 4.4 File Naming Conventions

- Format Detection by Extension:

  - *.xlsx*, *.XLSX*: OOXML Workbook.
  - *.ods*, *.ODS*: ODF Workbook.
  - No extension or other extension: CSV.

- Unquoted Filenames:

  - Converted to uppercase.

  - Default extension appended if none present:

    - Data files (*USE*/*SAVE*): *.CSV*
    - Console output files (*OUTPUT*): *.DAT*
    - Scripts (*SUBMIT*): *.CMD*

- **Explicit Format Specification:** Format may be specified explicitly with *FMT* option on *USE* and *SAVE* commands, overriding extension-based detection.

### 4.5 Error Handling

- Permission Errors:

  - Attempt to read file without permission: fails with error message.
  - Attempt to write file without permission: fails with error message.

- File System Errors:

  - Non-existent input file: fails with error message.
  - Non-existent target directory for output: fails with error message.
  - Permission verification for *SAVE*/*OUTPUT*: performed immediately when statement executed.

- Character Set Errors:

  - Invalid characters in detected/specified charset (*USE*): fails with error message.
  - Characters not representable in output charset (*SAVE*): fails with error message.

- **Data Integrity:** For *SAVE* and *OUTPUT* statements, interpreter shall immediately verify:

  - Target directory exists - User has permission to create target file OR overwrite existing file.
  - If conditions not met: statement fails with error message.

## 5. EXECUTION MODEL

### 5.1 The Data Step

The interpreter operates in a “data step” model where statements are executed for each record (row) in the internal table.

Record Iteration:

- When *USE* statement is in effect:

  - Statements execute once per record read from input dataset.

- When *REPEAT* statement is in effect:

  - Statements execute n times, creating records.
  - Current record context maintained throughout execution.

Record Processing:

- Each record read or created becomes the “current record”.
- Variable values for current record accessible to all statements.
- Output record written when data step completes for that record.

### 5.2 BY Group Processing

- **Purpose:** *BY* statement divides input into blocks based on variable value combinations.

- Grouping Rules:

  - Blocks defined by consecutive records with same combination of *BY* variable values.
  - New block begins whenever ANY *BY* variable value changes.
  - Blocks with same value combination but not consecutive are treated as separate blocks.
  - Blocks need not be in sorted order.
  - Missing values in *BY* variables treated as distinct values for grouping purposes.

- **Requirements:** - *USE* statement must be in effect; otherwise *BY* statement fails with error message

- Functions:

  - *BOG()*: True (1) at beginning of *BY* group, false (0) otherwise.
  - *EOG()*: True (1) at end of BY group, false (0) otherwise.
  - If *BY* statement not in effect, *BOG()* behaves like *BOF()*, *EOG()* behaves like *EOF()*.

### 5.3 Control Flow

#### Nesting

- Looping Blocks:

  - *FOR*/*NEXT*, *REPEAT*/*UNTIL*, *WHILE*/*WEND* may be nested inside each other.
  - Limited only by available stack space.
  - Running program fails with error message if it runs out of memory (user responsibility to prevent).

- Conditional Blocks:

  - *IF*/*THEN*/*ELSE* blocks may also be nested.
  - Same stack space limitations apply.

Looking blocks may also be nested inside of conditional blocks and vice versa.

#### Control Structures

- IF/THEN/ELSE:

  - Standard conditional execution.
  - May be nested.
  - *ELSEIF* supported for multi-way branching.

- FOR/NEXT:

  - Counter-controlled iteration.
  - As specified in BW BASIC documentation.

- WHILE/WEND:

  - Condition-controlled iteration.
  - Loop continues while condition is true.

- REPEAT/UNTIL:

  - Condition-controlled iteration.
  - Loop continues until condition becomes true.
  - **Note:** Also used as *REPEAT* command (different purpose).

- SELECT/CASE:

  - Multi-way branching.
  - Case-based selection.

### 5.4 Declarative vs Non-Declarative Statements

- Declarative Statements:

  - May not appear in *FOR*, *WHILE*, or *REPEAT*/*UNTIL* blocks.
  - Examples: *USE*, *SAVE*, *KEEP*, *DROP*, *BY*, *DIM*, *ARRAY*, *DIGITS*, *OPTIONS*.
  - Command reference table indicates which commands are declarative.

- Non-Declarative Statements:

  - May appear anywhere, including inside loops.
  - Examples: *LET*, *SET*, *PRINT*, *IF*, *DELETE* (record).

- **Line Continuation:** Statement ending with comma shall be continued to next line.

### 5.5 USE and REPEAT Compatibility

A *USE* statement and a *REPEAT* statement cannot both be in effect at the same time, and no more than one of either can be in effect at the same time.

Mutual Cancellation:

- *USE* statement cancels any *REPEAT* or *USE* statement currently in effect.

- *REPEAT* statement cancels any *USE* or *REPEAT* statement currently in effect.

  - Either cancels any non-declarative statements currently in effect.

**Note:** This refers to the *REPEAT* command (specify number of records), not *REPEAT*/*UNTIL* loop.

### 5.6 Script Execution

**SUBMIT Statement:** Reads and executes commands from specified file.

- Restrictions:

  - If *SUBMIT* appears inside *IF*, *FOR*, *WHILE*, or *REPEAT*/*UNTIL* block, submitted file may not contain declarative statements.
  - File may contain one or more *SUBMIT* statements.

- Recursion Prevention:

  - *SUBMIT* statement that attempts to submit a file already in the current execution chain fails with error message.
  - This prevents both: - Direct recursion (A → A) - Indirect recursion (A → B → A).

- **Execution Chain:** Sequence of files currently being executed via nested *SUBMIT* statements.

## 6. INPUT/OUTPUT

### 6.1 Console Output

By default, console output is written to standard output. If an *OUTPUT* file is

specified, output is written to **both** the file and standard output, unless the *-q* flag

or *ECHO OFF* is in effect.

- Character Sets:

  - Default: System locale.

  - Override:

    - *CHARSET* option on *OUTPUT* command, or *OPTIONS CHARSET*.
    - *OPTIONS CHARSET* sets default for subsequent *OUTPUT* files but doesn’t affect currently open file.

- Line Endings:

  - Default: Standard for platform.
  - Override: *FMT* option on OUTPUT command, or *OPTIONS TXTFMT.*
  - *OPTIONS TXTFMT* sets default for subsequent *OUTPUT* files but doesn’t affect currently open file.

- Output Control:

  - *ECHO* command:

    - Enables or disables writing console output to standard output.
    - Enabled by default.

### 6.2 The PRINT Command

- **Purpose:** Output values to console.

- Syntax:

  - *PRINT \[\<value\>...\]*: Print specified values separated by spaces.
  - *PRINT* (no arguments): Print values of all currently defined permanent variables with their names for current record.

- **Number Formatting:** Floating point values printed with precision specified by most recently issued *DIGITS* statement.

### 6.3 Interactive Mode

In interactive mode, declarative commands such as *USE*, *NAMES*, *OUTPUT*, *DIGITS*, and *ECHO* execute immediately upon entry to provide real-time feedback:

- **Prompt:** “*\>”* shall be used as the prompt.
- **Statement Echo:** Statements shall be echoed to screen, even if console output is disabled.
- **Terminal Handling:** Any applicable terminal settings shall be handled appropriately.
- **Paging:** If output text would otherwise scroll off the screen, display a page at a time using: - Pager specified at command line, OR - Sensible default for the operating system
- **Console Control:** Interactive mode provides REPL (Read-Eval-Print-Loop) environment for command entry and immediate execution.

## 7. LANGUAGE REFERENCE

### 7.1 Commands

Commands control the flow of execution, manage data, and configure the interpreter. The table below lists all supported commands alphabetically. It should be noted that while all declarative commands are to be immediately executed, not all commands to be immediately executed are declarative. Statements that are not to be immediately executed (“deferred execution statements”) become part of the program to be executed when the next RUN statement is executed.

<table>
<tbody>
<tr>
<td>Command</td>
<td>Syntax</td>
<td>Type</td>
<td>Description</td>
</tr>
<tr>
<td><em>ARRAY</em></td>
<td><em>ARRAY </em>&lt;<em>array name</em>&gt; [&lt;&gt;...]</td>
<td>Declarative</td>
<td>Create a virtual array consisting of the variables specified (comma delimited list). Specifying the array name without the list undefines any virtual arrays by that name (but not any actual arrays). Issuing the command only lists the virtual arrays currently defined. Virtual arrays may be referenced in exactly the same ways as actual arrays created by the <em>DIM</em> command. If an actual array with the name specified already exists then the command shall fail with an error message. If a virtual array with the name specified exists then the new definition shall replace the old one. All variables constituting the new array must exist and must be of the same type.</td>
</tr>
<tr>
<td><em>BY</em></td>
<td><em>BY</em> [&lt;<em>varname</em>&gt;...]</td>
<td>Declarative</td>
<td>Divide the input into blocks defined by the combination of variable values. An empty <em>BY</em> statement cancels any <em>BY</em> statement currently in effect. A new <em>BY</em> statement overrides any <em>BY</em> statement currently in effect. Blocks are defined by consecutive records with the same combination of <em>BY</em> variable values. A new block begins whenever any <em>BY </em>variable value changes, even if a previous block had the same combination of values. The blocks need not be in sorted order. Missing values in the named variables shall be treated as distinct values for grouping purposes. If no <em>USE</em> statement is in effect then a <em>BY</em> statement shall fail with an error message.</td>
</tr>
<tr>
<td><em>DELETE</em></td>
<td><em>DELETE</em> &lt;<em>line</em>&gt; [<em>-</em> &lt;<em>line</em>&gt;]</td>
<td>Immediate Execition</td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>DELETE</em></td>
<td><em>DELETE</em></td>
<td>Deferred Execution</td>
<td>Delete the current record and start processing the next record.</td>
</tr>
<tr>
<td><em>DIGITS</em></td>
<td><em>DIGITS(n)</em></td>
<td>Declarative</td>
<td><p>As specified in the BW BASIC documentation.</p>
<p>This sets the maximum number of decimal places to display (default = 3).</p></td>
</tr>
<tr>
<td><em>DIM</em></td>
<td><em>DIM</em> &lt;<em>arrayname</em>&gt; <em>([</em>&lt;<em>lower</em>&gt; <em>TO ] </em>&lt;<em>upper&gt;)</em> [<em>/TEMP</em>]</td>
<td>Declarative</td>
<td>As specified in the BW BASIC documentation, except that <em>&lt;filenum&gt;</em> is not supported.  The array is saved to the output dataset as a set of subscripted variables.  Appending <em>/TEMP </em>to a <em>DIM</em> statement shall create a temporary array which not be written to output datasets . A <em>DIM </em>statement that references an existing variable or array shall fail with an error message.</td>
</tr>
<tr>
<td><em>DROP</em></td>
<td><em>DROP</em> &lt;&gt;...</td>
<td>Declarative</td>
<td>Prevent one or more permanent variables from being retained after the next <em>RUN</em> statement is executed. The affected variables may not be referenced after they given in a <em>DROP</em> statement, but may be redefined with a <em>LET</em> or <em>SET</em> statement. Individual array elements cannot be deleted. Once given, a <em>DROP</em> statement may only be canceled by deleting it.</td>
</tr>
<tr>
<td><em>ECHO</em></td>
<td><em>ECHO</em> &lt;<em>ON</em> | <em>OFF</em>&gt;</td>
<td>Declarative</td>
<td>Enable or disable the writing of console output to standard output. Enabled by default.</td>
</tr>
<tr>
<td><em>FOR</em>/<em>NEXT</em></td>
<td></td>
<td>Deferred execution</td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>FPATH</em></td>
<td><em>FPATH</em> [&lt;<em>path</em>&gt;] <em>/ </em>[<em>OUTPUT</em> | <em>SAVE</em> | <em>SUBMIT</em> | <em>USE</em>]</td>
<td>Declarative</td>
<td>Set the default directory for input/output commands. <em>FPATH</em> without argument or flags resets all default directories to the current working directory. <em>&lt;path&gt;</em> is the relative or absolute path to the new default directory. If quoted, then it shall be taken literally. Otherwise, it will be taken as an expression signifying the path name to be used. The flags specify the command for which the default directory is to be set or unset. If <em>&lt;path&gt;</em> is not specified, then the existing relevant default directories shall be reset to the current working directory. Multiple commands may be specified with a comma-delimited list. If no flag is specified, then the default directory is set or unset for all commands.</td>
</tr>
<tr>
<td><em>HELP</em></td>
<td><em>HELP</em> [<em>command <em>| </em>/ALL</em>]</td>
<td>Immediate Execution</td>
<td>Display online help for the given command. If no command is given, then list the supported commands together with instructions on how to get help for individual commands and functions. <em>HELP /ALL</em> prints <em>HELP</em> for all commands and functions. </td>
</tr>
<tr>
<td><em>HOLD</em></td>
<td><em>HOLD </em>[&lt;<em>varname</em>&gt; ... ]</td>
<td>Declarative</td>
<td>By default, permanent variables are initialized to missing immediately before a new record is read in. This command disables this behavior for the variables named; or for all permanent variables if none are listed. A new <em>HOLD</em> statement cancels any previously issued.</td>
</tr>
<tr>
<td><em>IF</em>/<em>THEN</em>/<em>ELSE</em>/<em>ELSEIF</em>/<em>END IF</em></td>
<td></td>
<td>Deferred Execution</td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>KEEP</em></td>
<td><em>KEEP</em> [&lt;<em>varname</em>&gt;...]</td>
<td>Declarative</td>
<td>Specifies which variables will be retained after the next <em>RUN</em> statement is executed. If no variables are specified, then any <em>KEEP</em> statement currently in effect will be canceled and all permanent variables not already deleted shall be retained. Individual array elements may not appear in a <em>KEEP</em> statement. A <em>KEEP</em> statement that lists variables that either do not exist or have been deleted with a <em>DROP</em> statement shall fail with an error message.</td>
</tr>
<tr>
<td><em>LET</em></td>
<td></td>
<td>Deferred Execution</td>
<td><p>As specified in the BW BASIC documentation.</p>
<p>Defines permanent variables (those in the internal table) only. A <em>LET</em> statement that writes to a temporary variable shall make that variable permanent.</p></td>
</tr>
<tr>
<td><em>LIST</em></td>
<td></td>
<td>Immediate Execution</td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>NAMES</em></td>
<td><em>NAMES</em></td>
<td>Immediate Execution</td>
<td>Display the names of the currently defined variables, listing permanent and temporary variables separately.</td>
</tr>
<tr>
<td><em>NEW</em></td>
<td></td>
<td>Immediate Execution</td>
<td>As specified in the BW BASIC documentation. In addition, any declarative statements in effect, except for <em>OUTPUT</em>, are canceled.</td>
</tr>
<tr>
<td><em>OPTIONS</em></td>
<td><em>OPTIONS</em> [<em>key value</em>]</td>
<td>Immediate Execution</td>
<td>Set or display runtime options. With no arguments, lists all current option values. Notable keys: <em>MAXINTAB n</em> (max in-memory table cells; 0 = unlimited), <em>MAXTEMPMEM n</em> (max temporary variables; 0 = unlimited), <em>CSVDLM delim</em> (CSV field delimiter), <em>HEADER YES|NO</em> (CSV header row; default YES), <em>SAVEOVERWRT YES|NO</em> (overwrite on SAVE; default YES), <em>TXTFMT AUTO|LF|CRLF|CR</em> (CSV line ending; default AUTO), <em>CHARSET name</em> (character set label), <em>IEEE_DIVIDE YES|NO</em> (float /0 → ±Inf; default NO), <em>SHELLTIMEOUT n</em> (SYSTEM/SHELL timeout in seconds; 0 = unlimited; reset by NEW), <em>PROGRESS YES|NO</em> (emit record-count progress on stderr for long USE/RUN/SORT runs; default NO), <em>JOIN_WARN_THRESHOLD n</em> (Cartesian product warning threshold for /JOIN merges; default 1,000,000; 0 = disable), <em>WARNRESERVED YES|NO</em> (warn when a loaded column name matches a reserved keyword; default YES), <em>DEBUG n</em> (verbosity level for --debug mode; 0 = off).</td>
</tr>
<tr>
<td><em>OUTPUT</em></td>
<td><em>OUTPUT</em> [<em>filename</em>] [<em>/ [CHARSET =</em> &lt;<em>AUTO </em>| <em>UTF-8</em> |<em> UTF-16</em> |<em> ASCII&gt;</em>] | [<em>FMT =</em> &lt;<em>AUTO</em> | <em>LF</em> | <em>CRLF</em> | <em>CR</em>&gt;] ...]</td>
<td>Yes</td>
<td>Redirect console output to a file, or cancel an existing redirection. File names shall be interpreted in the same manner as by the <em>USE</em> command, except that the file format shall be text, regardless of the extension; and the default extension shall be “.DAT”. If no file name is specified, then any <em>OUTPUT</em> statement in effect shall be canceled and console output shall be written to standard output only. The <em>CHARSET</em> option shall specify the character set to be used to write the console output (<em>AUTO </em>specifies the default character set for the session locale and is the default unless changed by <em>OPTIONS CHARSET</em>). The <em>FMT</em> option shall determine the text line ending (<em>AUTO</em> shall specify the system default and is the default).</td>
</tr>
<tr>
<td><em>PRINT</em></td>
<td><em>PRINT</em> [&lt;<em>value</em>&gt;...]</td>
<td>Deferred Execution</td>
<td>Print one or more values separated by spaces. If no arguments are given, then print the values all currently defined permanent variables with their names for the current record. Floating point values shall be printed with the precision specified by the most recently issued <em>DIGITS</em> statement.</td>
</tr>
<tr>
<td><em>QUIT</em>|<em>END</em></td>
<td></td>
<td>Immediate Execution</td>
<td>As specified in the BW BASIC documentation. Initially, <em>END</em> shall be an alias for <em>QUIT</em>.</td>
</tr>
<tr>
<td><em>REM</em></td>
<td></td>
<td>Immediate Execution</td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>RENAME</em></td>
<td><em>RENAME </em>&lt;<em>oldname = newname, …&gt;</em></td>
<td>Declarative</td>
<td><p>Rename one or more variables. A renamed variable may not assigned the name of an existing variable unless it has been <em>DROP</em>ped. If the variable is permanent then it will take the new name in the output dataset if there is one.</p>
<p>Any statements following a <em>RENAME</em> statement must reference the affected variables under their new names. A numeric variable may not be assigned a character variable name and vice versa.</p></td>
</tr>
<tr>
<td><em>REPEAT</em></td>
<td><em>REPEAT</em> &lt;<em>n</em>&gt;</td>
<td>Declarative</td>
<td>Specify the number of records to be written to the internal table or output dataset. This command will cancel any <em>USE</em> statement currently in effect.</td>
</tr>
<tr>
<td><em>REPEAT</em>/<em>UNTIL</em></td>
<td></td>
<td>Deferred Execution</td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>RSEED</em></td>
<td><em>RSEED</em> &lt;<em>n</em>&gt;</td>
<td>Deferred Execution</td>
<td>Set the random number seed to the specified value (must be a literal integer). Persists until changed. At the beginning of each session, the random number seed is set from the system time.</td>
</tr>
<tr>
<td><em>RUN</em></td>
<td></td>
<td>Immediate Execution</td>
<td>As specified in the BW BASIC documentation.  Following the execution of any statements then in effect, the internal table is written to the output dataset specified by the <em>SAVE</em> command (if there is one).  If a variable appears in both the current <em>KEEP</em> statement and a subsequent <em>DROP </em>statement, then the latter shall take precedence. Once the program is run, the numbers of records and variables are displayed.</td>
</tr>
<tr>
<td><em>SAVE</em></td>
<td><em>SAVE</em> [ &lt;<em>filename</em>&gt;] [<em>/</em> [<em>FMT =</em> &lt;<em>CSV</em> | <em>ODF</em>|<em> OOXML</em> | <em>MSEXCEL</em>&gt;] | [<em> CHARSET =</em> &lt;<em>ASCII </em>| <em>UTF-8</em> | <em>UTF-16</em> | &lt; <em>csname</em> &gt;&gt; ] | [ <em>HEADER = </em>&lt;<em>YES</em> | <em>NO</em>&gt;] [<em>DLM = </em>&lt;<em>dlmstr</em>&gt;]...]</td>
<td>Declarative</td>
<td>Specify the file to which the table produced by the <em>RUN</em> command will be written. The file name shall be interpreted in the same way as by the <em>USE</em> command. The column names shall be as stored in the internal table. If no file name is specified, then any <em>SAVE</em> statement in effect shall be canceled. The <em>FMT</em> option governs the output file format (<em>OOXML</em> and <em>MSEXCEL</em> are equivalent). The <em>HEADER</em> option determines whether a header is written to the output file or spreadsheet. The <em>DLM</em> option sets the field delimiter on CSV files (string must be quoted). Variables shall be written in the order in which they appear in the internal table.</td>
</tr>
<tr>
<td><em>SELECT</em></td>
<td><em>SELECT</em> &lt;<em>expr</em>&gt;...</td>
<td><p>Declarative</p></td>
<td>Process only the subset of the data described by the comma-delimited set of boolean expressions.</td>
</tr>
<tr>
<td><em>SELECT CASE</em>/<em>CASE</em>/<em>CASE END</em></td>
<td></td>
<td>Deferred Execution</td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>SET</em></td>
<td><em>SET</em> &lt;<em>varname</em>&gt; <em>=</em> &lt; <em>expr</em>&gt;</td>
<td>Deferred Execution</td>
<td>Write the output of the expression to a temporary variable, which will disappear after the next <em>RUN</em> statement is executed. A <em>SET</em> statement that attempts to write to a permanent variable will fail with an error message.</td>
</tr>
<tr>
<td><em>SORT</em></td>
<td><em>SORT</em> &lt; <em>varname</em>&gt;...</td>
<td>Immediate Execution</td>
<td>Sort the output dataset by the variables named.</td>
</tr>
<tr>
<td><em>AGGREGATE</em></td>
<td><em>AGGREGATE</em> &lt;<em>outvar</em>&gt;=&lt;<em>fn</em>&gt;(&lt;<em>invar</em>&gt;) [&lt;<em>outvar</em>&gt;=&lt;<em>fn</em>&gt;(&lt;<em>invar</em>&gt;)...]</td>
<td>Immediate Execution</td>
<td>Collapse the data table to one row per active <em>BY</em> group, computing an aggregate function for each <em>outvar</em>. With no active <em>BY</em>, the whole table is one group. <em>fn</em> is any registered aggregate function (<em>SUM</em>, <em>MEAN</em>, <em>STD</em>, <em>VAR</em>, <em>MIN</em>, <em>MAX</em>, <em>N</em>, <em>NMISS</em>, <em>GMEAN</em>, <em>HMEAN</em>, <em>MEDIAN</em>); non-aggregate functions are rejected at parse time. An aggregate function accepts a character input only if its dispatch metadata permits it (currently only <em>N</em> and <em>NMISS</em>). <em>invar</em> may be a scalar column, a whole array (the output is an array with the input's bounds, computed element-wise), or an array element such as <em>x(1)</em>. Every function except <em>N</em> requires an argument; <em>N()</em> with no argument yields the integer group row count. The output table has the active BY variables (one row per group) followed by the outvar columns in command order. The active <em>SELECT</em> filter is respected during the group scan; if a <em>SAVE</em> is pending the result is written to it; then the active <em>SELECT</em> and <em>BY</em> are cleared. AGGREGATE refuses to run while un-run deferred statements are pending (issue <em>RUN</em> or <em>NEW</em> first). Note that because <em>BY</em> sorts the table, equal BY-key values are always grouped together even if they were non-adjacent in the input.</td>
</tr>
<tr>
<td><em>SUBMIT</em></td>
<td><em>SUBMIT</em> &lt;<em>filename</em> &gt;</td>
<td>Deferred Execution</td>
<td>Read and execute the commands contained in the specified file.  If the statement appears inside an <em>IF</em>, <em>FOR</em>, <em>WHILE</em>, or <em>REPEAT</em>/<em>UNTIL</em> block then the file may not contain any declarative statements. The file to be executed may contain one or more <em>SUBMIT</em> statements, but a <em>SUBMIT</em> statement that attempts to submit a file that is already in the current execution chain will fail with an error message.</td>
</tr>
<tr>
<td><em>SYSTEM</em></td>
<td><em>SYSTEM</em> [<em>&lt;cmd&gt;</em>]</td>
<td>Immediate execution</td>
<td>Execute the specified system command. If no command is given, then spawn a shell and resume the program when the shell exits. If the command is quoted, then it will be taken literally. Otherwise, it will be taken as the name of a variable or expression. If execution of a system command inside of a program is desired, then use the <em>SHELL</em> function.</td>
</tr>
<tr>
<td><em>UNHOLD</em></td>
<td><em>UNHOLD</em></td>
<td>Declarative</td>
<td>Cancel any <em>HOLD</em> statement currently in effect.</td>
</tr>
<tr>
<td><em>USE</em></td>
<td><em>USE</em> [<em>MOCK</em> | &lt;<em>filename</em>&gt;]<em> / NSCAN =</em> &lt;<em>n</em>&gt;</td>
<td>Declarative</td>
<td>Open a dataset for reading and display the names of the columns and the number of records. The internal table shall be overwritten with the contents of the file. Any column with a name that ends in “$” is assumed to be character. Otherwise, any column with non-numeric values in any of the first <em>n</em> rows (if there are that many) will be taken as character and “$” will be added to the name. If subsequently, a non-numeric value appears in such a column, it will be taken as missing and a warning will be issued (maximum of 10 shall be written). If a column name appears more than once in the file, only the last column with the name will be used and a warning shall be issued. If the file name is unquoted, it is converted to uppercase. If the name is unquoted and has no extension,<em>  </em>“.CSV” is appended to the name. The default directory is the current working directory unless changed by the <em>FPATH</em> command. The format of the file will be assumed based on the file name extension. Any <em>DROP</em>, <em>KEEP</em>, <em>LET</em>, <em>or</em> <em>REPEAT</em> statements are canceled when a new dataset is read in. <em>USE MOCK</em> generates mock data for testing purposes.</td>
</tr>
<tr>
<td><em>WHILE</em>/<em>WEND</em></td>
<td></td>
<td>Deferred Execution</td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>WRITE</em></td>
<td><em>WRITE</em></td>
<td>Deferred Execution</td>
<td>Explicitly write the current record (PDV) to the data table. Suppresses the default record output at the end of the Data Step.</td>
</tr>
</tbody>
</table>

Deferred Execution Commands are part of the program that is executed with the next *RUN* statement. Statements and blocks are executed in the order in which they were entered. The currently defined program may be listed with the *LIST* command. Statements may be deleted with the *DELETE* command.

**Declarative Commands** are executed immediately. They typically configure the interpreter state or define data structures.

**Line Continuation:** A statement ending with a comma shall be continued to the next line.

### 7.2 Functions

Functions perform computations and return values. Unless otherwise stated:

<table>
<tbody>
<tr>
<td>Name</td>
<td>Usage</td>
<td>Constraints</td>
<td>Description</td>
</tr>
<tr>
<td><em>ABS</em></td>
<td><em>ABS(<em>x</em>)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>ARCCOS</em></td>
<td><em>ARCCOS(<em>x</em>)</em></td>
<td>-1 ≤ <em><em>x</em></em> ≤ 1</td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>ARCSIN</em></td>
<td><em>ARCSIN(x)</em></td>
<td>-1 ≤ <em><em>x</em></em> ≤ 1</td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>ARCTAN</em></td>
<td><em>ARCTAN(x)</em></td>
<td></td>
<td>As specified in the BW BASIC. documentation</td>
</tr>
<tr>
<td><em>ASCII</em></td>
<td><em>ASCII(A$)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>BCF</em></td>
<td><em>BCF(β, p, q)</em></td>
<td><p>0 ≤ <em>β ≤ 1</em></p>
<p><em>p &gt; 0</em></p>
<p><em>q &gt; 0</em></p></td>
<td>Return the value of the cumulative distribution function for the beta distribution, where <em>β </em>is the evaluation point and <em>p </em>and <em>q </em>are the alpha and beta shape parameters.</td>
</tr>
<tr>
<td><em>BDF</em></td>
<td><em>BDF(β, p, q)</em></td>
<td><p>0 ≤ <em>β ≤ 1</em></p>
<p><em>p &gt; 0</em></p>
<p><em>q &gt; 0</em></p></td>
<td>Return the value of the beta density function where <em>β </em>is the evaluation point and <em>p </em>and <em>q </em>are the alpha and beta shape parameters.</td>
</tr>
<tr>
<td><em>BIF</em></td>
<td><em>BIF(ᶲ, p, q)</em></td>
<td><p>0 ≤ <em>ᶲ ≤ 1</em></p>
<p><em>p &gt; 0</em></p>
<p><em>q</em> <em> &gt; 0</em></p></td>
<td>Return the value of the inverse probability density function for the beta distribution, where <em>ᶲ </em> is the probability.<em> </em>and <em>p </em>and <em>q </em>are the alpha and beta shape parameters.</td>
</tr>
<tr>
<td><em>BIN$</em></td>
<td><em>BIN$(X, Y%)</em></td>
<td>0 ≤ <em>Y%</em> ≤ 255</td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>BOF</em></td>
<td>No arguments</td>
<td></td>
<td>True (1) for the first record of a dataset and false (0) otherwise.</td>
</tr>
<tr>
<td><em>BOG</em></td>
<td>No arguments</td>
<td></td>
<td>True (1) at the beginning of a <em>BY</em> group and false (0) otherwise. Same output as <em>BOF</em> if a <em>BY</em> statement is not in effect.</td>
</tr>
<tr>
<td><em>BRN</em></td>
<td><em>BRN(p, q)</em></td>
<td><p><em>p &gt; 0</em></p>
<p><em>q &gt; 0</em></p></td>
<td>Return a random number from the beta distribution. <em>p</em> and <em>q</em> are the alpha and beta shape parameters. Both must be greater than 0.</td>
</tr>
<tr>
<td><em>CLG</em></td>
<td><em>CLG(X)</em></td>
<td><em>X</em> &gt; 0</td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>COS</em></td>
<td><em>COS(X)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>COSD</em></td>
<td><em>COSD(X)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>COT</em></td>
<td><em>COT(X)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>CSC</em></td>
<td><em>CSC(X)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>DEG</em>/<em>DEGREE</em></td>
<td><em>DEG(x)</em></td>
<td></td>
<td>Convert <em>x</em> from radians to degrees.</td>
</tr>
<tr>
<td><em>ECF</em></td>
<td><em>ECF(x)</em></td>
<td>0 ≤ <em>x ≤ 1</em></td>
<td>Return the value of the cumulative distribution function of the exponential distribution where <em>x</em> is the evaluation point.</td>
</tr>
<tr>
<td><em>EDF</em></td>
<td><em>EDF(x)</em></td>
<td>0 ≤ <em>x ≤ 1</em></td>
<td>Return the value of the probability density function of the exponential distribution where <em>x</em> is the evaluation point.</td>
</tr>
<tr>
<td><em>EIF</em></td>
<td><em>EIF(ᶲ)</em></td>
<td>0 ≤ <em>ᶲ </em>≤ 1</td>
<td>Return the value of the inverse probability density function of the exponential distribution where <em>ᶲ</em> is the probability.</td>
</tr>
<tr>
<td><em>EOF</em></td>
<td>No arguments</td>
<td></td>
<td>True (1) for the last record of the input dataset and false (0) otherwise.</td>
</tr>
<tr>
<td><em>EOG</em></td>
<td>No arguments</td>
<td></td>
<td>True (1) for the last record of a <em>BY</em> group and false (0) otherwise. Same value as <em>EOF</em> if a <em>BY</em> statement is not in effect.</td>
</tr>
<tr>
<td><em>ERN</em></td>
<td><em>ERN</em></td>
<td></td>
<td>Return a random number in the exponential distribution.</td>
</tr>
<tr>
<td><em>EXP</em></td>
<td><em>EXP(X)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>FALSE</em></td>
<td>No arguments</td>
<td></td>
<td>Return 0, which is taken as false.</td>
</tr>
<tr>
<td><em>FCF</em></td>
<td><em>FCF(F, df1, df2)</em></td>
<td><p>0 ≤ <em>F</em> ≤ 1</p>
<p><em>df1 </em>&gt; 0</p>
<p><em>df2 </em>&gt; 0</p></td>
<td>Return the value of the cumulative distribution function of the F distribution where <em>F</em> is the evaluation point and <em>df1</em> and <em>df2</em> are the set of degrees of freedom.</td>
</tr>
<tr>
<td><em>FDF</em></td>
<td><em>FDF(F, df1, df2)</em></td>
<td><p>0 ≤ <em>F</em> ≤ 1</p>
<p><em>df1 </em>&gt; 0</p>
<p><em>df2 </em>&gt; 0</p></td>
<td>Return the value of the probability density function of the F distribution where <em>F</em> is the evaluation point and <em>df1</em> and <em>df2</em> are the set of degrees of freedom.</td>
</tr>
<tr>
<td><em>FIF</em></td>
<td><em>FIF(ᶲ, df1, df2</em>)</td>
<td><p>0 ≤ <em>ᶲ</em> ≤ 1</p>
<p><em>df1 </em>&gt; 0</p>
<p><em>df2 </em>&gt; 0</p></td>
<td>Return the value of the inverse probability density function of the F distribution where <em>ᶲ</em> is the probability and <em>df1</em> and <em>df2</em> are the set of degrees of freedom.</td>
</tr>
<tr>
<td><em>FIX</em></td>
<td><em>FIX(X)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation</td>
</tr>
<tr>
<td><em>FP</em>/<em>FRAC</em></td>
<td><em>FP(X)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation</td>
</tr>
<tr>
<td><em>FRN</em></td>
<td><em>FRN(df1, df2)</em></td>
<td><p><em>df1 </em>&gt; 0</p>
<p><em>df2 </em>&gt; 0</p></td>
<td>Return a random number in the F distribution, where <em>df1</em> and <em>df2</em> are the set of degrees of freedom.</td>
</tr>
<tr>
<td><em>GCF</em></td>
<td><em>GCF(γ, p)</em></td>
<td><p>0 ≤ <em>γ</em> ≤ 1</p>
<p><em>p</em> &gt; 0</p></td>
<td>Return the value of the cumulative distribution function of the gamma distribution where  <em>γ </em>is the evaluation point and <em>p </em>is the shape parameter.</td>
</tr>
<tr>
<td><em>GDF</em></td>
<td><em>GDF(γ, p)</em></td>
<td><p>0 ≤ <em>γ</em> ≤ 1</p>
<p><em>p</em> &gt; 0</p></td>
<td>Return the value of the gamma density function where <em>γ </em>is the evaluation point and <em>p </em>is the shape parameter.</td>
</tr>
<tr>
<td><em>GIF</em></td>
<td><em>GIF(ᶲ, p)</em></td>
<td><p>0 ≤ <em>ᶲ</em> ≤ 1</p>
<p><em>p</em> &gt; 0</p></td>
<td>Return the value of the inverse probability density function of the gamma distribution where <em>ᶲ </em>  is the probability and <em>p </em>is the shape parameter.</td>
</tr>
<tr>
<td><em>GMEAN</em></td>
<td><em>GMEAN(</em>&lt;<em>value</em>...&gt;<em>)</em></td>
<td></td>
<td>Return the geometric mean of the arguments. All elements in any arrays specified shall be used. Missing values shall be ignored.</td>
</tr>
<tr>
<td><em>GRN</em></td>
<td><em>GRN(p)</em></td>
<td><em>p</em> &gt; 0</td>
<td>Return a random number in the gamma distribution where <em>p</em> is the shape parameter.</td>
</tr>
<tr>
<td><em>HCS</em></td>
<td><em>HCS(X)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>HEX</em></td>
<td><em>HEX(A$)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>HEX$</em></td>
<td><em>HEX$(X, Y)</em></td>
<td>0 &lt; <em>Y <em>≤</em></em> 255</td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>HMEAN</em></td>
<td><em>HMEAN(</em>&lt;<em>value</em>&gt;...<em>)</em></td>
<td></td>
<td>Return the harmonic mean of the arguments. If an array is specified, then all elements shall be used. Missing values shall be ignored.</td>
</tr>
<tr>
<td><em>HSN</em></td>
<td><em>HSN(X)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>HTN</em></td>
<td><em>HTN(X)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>INDEX</em></td>
<td><em>INDEX(A$, B$)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation</td>
</tr>
<tr>
<td><em>INSTR</em></td>
<td>INSTR(<em>X%</em>, <em>A$</em>, <em>B$</em>)</td>
<td></td>
<td>As specified in the BW BASIC documentation</td>
</tr>
<tr>
<td><em>INT</em></td>
<td><em>INT(X)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation</td>
</tr>
<tr>
<td><em>IP</em></td>
<td><em>IP(X)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation</td>
</tr>
<tr>
<td><em>LAG</em></td>
<td><em>LAG(</em>&lt;<em>varname</em>&gt; [<em>, </em>&lt;<em>n</em>&gt;]<em>)</em></td>
<td><em>n</em> &gt; 0</td>
<td>Return the <em>n</em>th prior value of the specified scalar variable, array, or array subset of any type. If <em>n</em> is unspecified then it will default to 1. If an array or array subset is specified, an array of the same size is returned. If there are fewer than <em>n</em> prior records, then return a missing value or an array of missing values as the case may require. The value returned will always be of the same type as the specified variable. If a <em>BY</em> statement is in effect then the search shall be restricted to records within the current <em>BY</em> group.</td>
</tr>
<tr>
<td><em>LBOUND</em></td>
<td><em>LBOUND(arrayname)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>LCASE$</em></td>
<td><em>LCASE$(A$)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>LCF</em></td>
<td><em>LCF(x)</em></td>
<td>0 ≤ <em>x</em> ≤ 1</td>
<td>Return the value of the cumulative distribution function of the logistic distribution where <em>x</em> is the evaluation point.</td>
</tr>
<tr>
<td><em>LDF</em></td>
<td><em>LDF(x)</em></td>
<td>0 ≤ <em>x</em> ≤ 1</td>
<td>Return the value of the inverse probability density function function of the logistic distribution where <em>x</em> is the evaluation point.</td>
</tr>
<tr>
<td><em>LIF</em></td>
<td><em>LIF(p</em>)</td>
<td>0 ≤ <em>p</em> ≤ 1</td>
<td>Return the value of the probability density function function of the logistic distribution where <em>p</em> is the probability.</td>
</tr>
<tr>
<td><em>LEFT$</em></td>
<td><em>LEFT$(A$, X)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>LEN</em></td>
<td><em>LEN(A$)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>LGT</em></td>
<td><em>LGT(X)</em></td>
<td><em>X</em> &gt; 0</td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>LN</em></td>
<td><em>LN(X)</em></td>
<td><em>X</em> &gt; 0</td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>LOG</em></td>
<td><em>LOG(X)</em></td>
<td><em>X</em> &gt; 0</td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>LOG10</em></td>
<td><em>LOG10(X)</em></td>
<td><em>X</em> &gt; 0</td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>LOG2</em></td>
<td><em>LOG2(X)</em></td>
<td><em>X</em> &gt; 0</td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>LOGE</em></td>
<td><em>LOGE(X)</em></td>
<td><em>X</em> &gt; 0</td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>LOWER$</em></td>
<td><em>LOWER$(A$)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>LRN</em></td>
<td><em>LRN</em></td>
<td></td>
<td>Return a random number in the logistic distribution.</td>
</tr>
<tr>
<td><em>LTRIM$</em></td>
<td><em>LTRIM$(A$)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>LTW</em></td>
<td><em>LTW(X)</em></td>
<td><em>X</em> &gt; 0</td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>MATCH</em></td>
<td><em>MATCH(A$, B$, X%)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>MAX</em></td>
<td><em>MAX(</em>&lt;<em>value</em>&gt;,...<em>)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation; except that any number of arguments shall be permitted and that all elements in any array arguments shall be compared.</td>
</tr>
<tr>
<td><em>MAXINT</em></td>
<td></td>
<td></td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>MAXLEN</em></td>
<td><em>MAXLEN(A$)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>MAXLVL</em></td>
<td></td>
<td></td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>MAXNUM</em></td>
<td></td>
<td></td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>MEAN</em></td>
<td><em>MEAN(v1, [v2, ...])</em></td>
<td></td>
<td>Return the arithmetic mean of the arguments. If an array is referenced, then all elements are included. Missing values shall be ignored.</td>
</tr>
<tr>
<td><em>MEDIAN</em></td>
<td><em>MEDIAN(</em>&lt;<em>value</em>&gt;...<em>)</em></td>
<td></td>
<td>Return the median value of the arguments. If an array is referenced, then all elements shall be included. Missing values shall be ignored.</td>
</tr>
<tr>
<td><em>MID$</em></td>
<td><em>MID$(A$, X%, Y%)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation</td>
</tr>
<tr>
<td><em>MIN</em></td>
<td><em>MIN(</em>&lt;<em>value</em>&gt;...<em>)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation; except that any number of arguments shall be permitted and that all elements in any array arguments shall be compared.</td>
</tr>
<tr>
<td><em>MININT</em></td>
<td></td>
<td></td>
<td>As specified in the BW BASIC documentation</td>
</tr>
<tr>
<td><em>MINNUM</em></td>
<td></td>
<td></td>
<td>As specified in the BW BASIC documentation</td>
</tr>
<tr>
<td><em>MISSING</em></td>
<td><em>MISSING(</em>&lt;<em>varname</em>&gt;<em>)</em></td>
<td></td>
<td>Return true if the referenced variable (character or numeric) is missing. If an array is referenced, then return true if any of the elements is missing. Otherwise return false.</td>
</tr>
<tr>
<td><em>MOD</em></td>
<td><em>MOD(X%, Y%)</em></td>
<td><em>Y%</em> ≠ 0</td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>NCF</em></td>
<td><em>NCF(x,n,p</em>)</td>
<td><p>0 ≤ <em>x ≤ 1</em></p>
<p><em>n &gt; 0</em></p>
<p><em>0 &lt;  p &lt; 1</em></p></td>
<td>Return the value of the cumulative distribution function for the binomial distribution where <em>x</em> is the evaluation point, <em>n</em> is the number of trials, and <em>p</em> is the probability of success in each trial.</td>
</tr>
<tr>
<td><em>NDF</em></td>
<td><em>NDF(x,n,p)</em></td>
<td><p>0 ≤ <em>x ≤ 1</em></p>
<p><em>n &gt; 0</em></p>
<p><em>0 &lt;  p &lt; 1</em></p></td>
<td>Return the value of the probability density function for the binomial distribution where <em>x</em> is the evaluation point, <em>n</em> is the number of trials, and <em>p</em> is the probability of success in each trial.</td>
</tr>
<tr>
<td><em>NEXT</em></td>
<td><em>NEXT(</em>&lt;<em>varname</em>&gt; [<em>, </em>&lt;<em>n&gt;</em>]<em>)</em></td>
<td><em>n &gt; 0</em></td>
<td>Return the <em>n</em>th succeeding value of the specified scalar variable, array, or array subset of any type. If <em>n</em> is unspecified then it shall default to 1. If an array or array subset is specified, an array of the same size is returned. If there are fewer than <em>n</em> succeeding records, then return a missing value or an array of missing values as the case may require. The value returned shall always be of the same type as the specified variable. If a <em>BY</em> statement is in effect then the search shall be restricted to records within the current <em>BY</em> group.</td>
</tr>
<tr>
<td><em>NMISS</em></td>
<td><em>NMISS(</em>&lt;<em>varname</em>&gt;...<em>)</em></td>
<td></td>
<td>Return the number of missing values in the arguments. For array arguments, all missing elements shall be counted.</td>
</tr>
<tr>
<td><em>NRN</em></td>
<td><em>NRN(n, p)</em></td>
<td><p><em>n &gt; 0</em></p>
<p><em>0 &lt;  p &lt; 1</em></p></td>
<td>Return a random number in the binomial distribution where <em>n</em> is the number of trials and <em>p</em> is the probability of success in each trial.</td>
</tr>
<tr>
<td><em>NUM</em></td>
<td><em>NUM(</em>&lt;<em>value</em>&gt;...<em>)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation, except that any number of arguments shall be accepted. If there is a single scalar argument, then a single value will be returned, otherwise an array containing one element per scalar argument or array argument element. Any individual array elements shall be treated as scalars. Only character arguments allowed.</td>
</tr>
<tr>
<td><em>NUM$</em></td>
<td><em>NUM$(</em>&lt;<em>value</em>&gt;...<em>)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation, except that any number of arguments shall be accepted and shall be processed as by <em>NUM</em>. Only numeric arguments shall be permitted.</td>
</tr>
<tr>
<td><em>OCT$</em></td>
<td><em>OCT$(X, Y% )</em></td>
<td>0 &lt; <em>Y%</em> ≤ 255</td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>ORD</em></td>
<td><em>ORD(A$)</em></td>
<td><em>LEN(A$)</em> &gt; 0</td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>PCF</em></td>
<td><em>PCF(x, p)</em></td>
<td><p>0 ≤ <em>x</em> ≤ 1</p>
<p>0 ≤ <em>p</em> ≤ 1</p></td>
<td>Return the value of the cumulative distribution function of the Poisson distribution where <em>x</em> is the evaluation point and <em>p</em> is the Poisson parameter.</td>
</tr>
<tr>
<td><em>PDF</em></td>
<td><em>PDF(</em>x<em>, p)</em></td>
<td><p>0 ≤ <em>x</em> ≤ 1</p>
<p>0 ≤ <em>p</em> ≤ 1</p></td>
<td>Return the value of the probability mass function of the Poisson distribution where <em>x</em> is the evaluation point and <em>p</em> is the Poisson parameter.</td>
</tr>
<tr>
<td><em>PI</em></td>
<td></td>
<td></td>
<td>As specified in the BW BASIC documentation, except that pi shall be returned as precisely as the word size will permit.</td>
</tr>
<tr>
<td><em>PIF</em></td>
<td><em>PIF(ᶲ, p)</em></td>
<td><p>0 ≤ <em>ᶲ</em> ≤ 1</p>
<p>0 ≤ <em>p</em> ≤ 1</p></td>
<td>Return the value of the inverse probability mass function of the Poisson distribution where <em>ᶲ</em> is the probability and <em>p</em> is the Poisson parameter.</td>
</tr>
<tr>
<td><em>POS</em></td>
<td><em>POS(A$, B$)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>POS</em></td>
<td><em>POS(A$, B$, X)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation</td>
</tr>
<tr>
<td><em>PRN</em></td>
<td><em>PRN(p)</em></td>
<td></td>
<td>Return a random number in the Poisson distribution where <em>p</em> is the Poisson parameter.</td>
</tr>
<tr>
<td><em>RAD</em>/<em>RADIAN</em></td>
<td><em>RAD(X)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>RIGHT$</em></td>
<td><em>RIGHT$(A$, X%)</em></td>
<td><em>X%</em> &gt; 0</td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>ROUND</em></td>
<td><em>ROUND(X, Y%)</em></td>
<td>Y% ≥ 0</td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>RTRIM$</em></td>
<td><em>RTRIM$(A$)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>SEC</em></td>
<td><em>RTRIM$(A$)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>SEG$</em></td>
<td><em>SEG$(A$, X%, Y%)</em></td>
<td><p><em>X%</em> ≥ 0</p>
<p><em>Y%</em> &gt; 0</p></td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>SGN</em></td>
<td><em>SGN(X)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>SHELL</em></td>
<td><em>SHELL(A$)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>SIN</em></td>
<td><em>SIN(X)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>SIND</em></td>
<td><em>SIND(X)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>SINH</em></td>
<td><em>SINH(X)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>SQR</em></td>
<td><em>SQR(X)</em></td>
<td>X ≥ 0</td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>STD</em></td>
<td><em>STD(v1, [v2, ...])</em></td>
<td></td>
<td>Return the standard deviation of the arguments, each element of any array arguments being treated as a single argument. Missing values shall be ignored.</td>
</tr>
<tr>
<td><em>SUM</em></td>
<td><em>SUM(v1, [v2, ...])</em></td>
<td></td>
<td>Row-wise sum. Arrays passed as arguments are expanded.</td>
</tr>
<tr>
<td><em>TAN</em></td>
<td><em>TAN(X)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>TAND</em></td>
<td><em>TAND(X)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>TANH</em></td>
<td><em>TANH(X)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>TCF</em></td>
<td><em>TCF(t, df)</em></td>
<td><p>0 ≤ <em>t </em>≤ 1</p>
<p><em>df </em>&gt; 0</p></td>
<td>Return the value of the cumulative distribution function of the T distribution where <em>t </em>is the evaluation point and <em>df </em>is the number of degrees of freedom.</td>
</tr>
<tr>
<td><em>TDF</em></td>
<td><em>TDF(t, df)</em></td>
<td><p>0 ≤ <em>t </em>≤ 1</p>
<p><em>df </em>&gt; 0</p></td>
<td>Return the value of the probability density function of the T distribution where <em>t </em>is the evaluation point and <em>df </em>is the number of degrees of freedom.</td>
</tr>
<tr>
<td><em>TIF</em></td>
<td><em>TIF(ᶲ, df)</em></td>
<td><p>0 ≤ <em>ᶲ </em>≤ 1</p>
<p><em>df </em>&gt; 0</p></td>
<td>Return the value of the inverse probability density function of the T distribution where <em>ᶲ </em>  is the probability and <em>df </em>is the number of degrees of freedom.</td>
</tr>
<tr>
<td><em>TIMER</em></td>
<td>No arguments</td>
<td></td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>TRIM$</em></td>
<td><em>TRIM$(A$)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>TRN</em></td>
<td><em>TRN(df)</em></td>
<td></td>
<td>Return a random number in the T distribution where <em>df</em> is the number of degrees of freedom.</td>
</tr>
<tr>
<td><em>TRUE</em></td>
<td>No arguments</td>
<td></td>
<td>Return 1, which is taken as true.</td>
</tr>
<tr>
<td><em>TRUNCATE</em></td>
<td><em>TRUNCATE(X, Y%)</em></td>
<td><em>Y%</em> ≥ 0</td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>UBOUND</em></td>
<td><em>UBOUND(arrayname)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>UCASE$</em></td>
<td><em>UCASE$(A$)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>UCF</em></td>
<td><em>UCF(x)</em></td>
<td><em>0 ≤ x ≤ 1</em></td>
<td>Return the value of the cumulative distribution function of the uniform distribution where <em>x</em> is the evaluation point.</td>
</tr>
<tr>
<td><em>UDF</em></td>
<td><em>UDF(x)</em></td>
<td><em>0 ≤ x ≤ 1</em></td>
<td>Return the value of the probability density function of the uniform distribution where <em>x</em> is the evaluation point.</td>
</tr>
<tr>
<td><em>UIF</em></td>
<td><em>UIF(ᶲ)</em></td>
<td><em>0 ≤ ᶲ ≤ 1</em></td>
<td>Return the value of the inverse probability density function of the uniform distribution where <em>ᶲ </em> is the probability.</td>
</tr>
<tr>
<td><em>UPPER$</em></td>
<td><em>UPPER$(A$)</em></td>
<td></td>
<td>As specified in the BW BASIC documentation.</td>
</tr>
<tr>
<td><em>URN</em></td>
<td>No arguments</td>
<td></td>
<td>Return a uniformly distributed random number between 0 and 1.</td>
</tr>
<tr>
<td><em>VAR</em></td>
<td><em>VAR(v1, [v2, ...])</em></td>
<td></td>
<td>Row-wise sample variance.</td>
</tr>
<tr>
<td><em>XCF</em></td>
<td><em>XCF(x, df)</em></td>
<td><p><em>0 ≤ x ≤ 1</em></p>
<p><em>df &gt; 0</em></p></td>
<td>Return the value of the cumulative distribution function of the chi square distribution where <em>x</em> is the evaluation point and <em>df</em> is the number of degrees of freedom.</td>
</tr>
<tr>
<td><em>XDF</em></td>
<td><em>XDF(x, df)</em></td>
<td><p><em>0 ≤ x ≤ 1</em></p>
<p><em>df &gt; 0</em></p></td>
<td>Return the value of the probability density function of the chi square distribution where <em>x</em> is the evaluation point and <em>df</em> is the number of degrees of freedom.</td>
</tr>
<tr>
<td><em>XIF</em></td>
<td><em>XIF(ᶲ, df)</em></td>
<td><p><em>0 ≤ ᶲ ≤ 1</em></p>
<p><em>df &gt; 0</em></p></td>
<td>Return the value of the inverse probability density function of the chi square distribution where <em>ᶲ </em>is the probability and <em>df </em>is the number of degrees of freedom.</td>
</tr>
<tr>
<td><em>XRN</em></td>
<td><em>XRN(df)</em></td>
<td><em>df &gt; 0</em></td>
<td>Return a random number in the chi square distribution where <em>df</em> is the number of degrees of freedom.</td>
</tr>
<tr>
<td><em>WCF</em></td>
<td><em>WCF(x, p, q</em>)</td>
<td><p>0 ≤ x ≤ 1</p>
<p><em>p</em> &gt; 0</p>
<p><em>q</em> &gt; 0</p></td>
<td>Return the value of the cumulative distribution function of the Weibull distribution where <em>x</em> is the evaluation point, <em>p</em> is the scale parameter, and <em>q</em> is the shape parameter.</td>
</tr>
<tr>
<td><em>WDF</em></td>
<td><em>WDF(x, p, q</em>)</td>
<td><p>0 ≤ x ≤ 1</p>
<p><em>p</em> &gt; 0</p>
<p><em>q</em> &gt; 0</p></td>
<td>Return the value of the probability density function of the Weibull distribution where <em>x</em> is the evaluation point, <em>p</em> is the scale parameter, and <em>q</em> is the shape parameter.</td>
</tr>
<tr>
<td><em>WIF</em></td>
<td><em>WIF(ᶲ, p, q</em>)</td>
<td><p>0 ≤ ᶲ ≤ 1</p>
<p><em>p</em> &gt; 0</p>
<p><em>q</em> &gt; 0</p></td>
<td>Return the value of the probability density function of the Weibull distribution where ᶲ is the probability, <em>p</em> is the scale parameter, and <em>q</em> is the shape parameter.</td>
</tr>
<tr>
<td><em>WRN</em></td>
<td><em>WRN(p, q</em>)</td>
<td><p><em>p</em> &gt; 0</p>
<p><em>q</em> &gt; 0</p></td>
<td>Return a random number on the Weibull distribution where <em>p</em> is the scale parameter, and <em>q</em> is the shape parameter.</td>
</tr>
<tr>
<td><em>ZCF</em></td>
<td><em>ZCF(x [, mu, sigma])</em></td>
<td><p>0 ≤<em> z</em> ≤ 1</p>
<p><em>sigma</em> &gt; 0</p></td>
<td><p>Returns the value of the cumulative     </p>
<p> distribution function of the normal distribution evaluated at <em>x</em>, where <em>mu</em> is the mean and <em>sigma</em> is the standard deviation. If <em>mu</em> and <em>sigma</em> are omitted, the Standard Normal distribution (mean 0, standard deviation 1) is used.</p></td>
</tr>
<tr>
<td><em>ZDF</em></td>
<td><em>ZDF(x [, mu, sigma])</em></td>
<td><p>0 ≤ <em>z</em> ≤ 1</p>
<p><em>sigma</em> &gt; 0</p></td>
<td><p>Returns the value of the probability    </p>
<p> density function of the normal distribution evaluated at <em>x</em>, where <em>mu</em> is the mean and <em>sigma</em> is the standard deviation. If <em>mu</em> and <em>sigma</em> are omitted, the Standard Normal    </p>
<p> distribution (mean 0, standard deviation 1) is used.</p></td>
</tr>
<tr>
<td><em>ZIF</em></td>
<td><em>ZIF(p [, mu, sigma])</em></td>
<td><p>0 ≤ <em>p</em> ≤ 1</p>
<p><em>sigma</em> &gt; 0</p></td>
<td><p>Returns the inverse    </p>
<p> cumulative distribution function (quantile) of the normal distribution for probability *p*, </p>
<p> where *mu* is the mean and *sigma* is the standard deviation. If *mu* and *sigma* are      </p>
<p> omitted, the Standard Normal distribution (mean 0, standard deviation 1) is used.</p></td>
</tr>
<tr>
<td><em>ZRN</em></td>
<td><em>ZRN([mu, sigma])</em></td>
<td><em>sigma</em> &gt; 0</td>
<td>Returns a random variate from the normal distribution where <em>mu</em> is the mean and <em>sigma</em> is the standard deviation. If arguments are omitted, the Standard Normal distribution (mean 0, standard deviation 1) is used.</td>
</tr>
</tbody>
</table>

- Functions returning character values end with *\$.*
- Functions returning numeric values do not end with *\$.*

Function Arguments:

- Variable ranges may not be function arguments.
- If numeric argument set to character value (or vice versa): function call fails with error.
- Argument values outside permitted range: function call fails with error.
- Invalid arguments to mathematical functions (e.g., non-positive argument to *LOG*): fails with error

**Aliases:** Multiple function names separated by “/” are aliases of the same function. All aliases shown in the function table shall be supported; additional aliases are not required.

Aggregate Functions:

- Ignore missing values when making computations.
- If no non-missing arguments passed: return missing value.

### 7.3 Operators and Expression Evaluation

**Operator Precedence:** As specified in BW BASIC documentation.

Expression Types:

- Arithmetic expressions: Numeric values, variables, and functions combined with arithmetic operators.
- String expressions: Character values, variables, and functions combined with string operators.
- Logical expressions: Boolean values resulting from comparisons and logical operations.

**Type Checking:** Type mismatches in expressions result in error messages (e.g., adding numeric to character value).

## 8. IMPLEMENTATION NOTES

### 8.1 Usage

*sdata* \[*-q -u\<filename\>* \[*--infmt=*\<csv\|odf\|ooxml\>\]\] \[*-s\<filename\>* \\

\[*--outfmt=*\<csv\|odf\|ooxml\>\]\] \[*-o \<filename\>*\] \[*-m*\<n\>**\]** \[*--clen=*\<n\>\] \\

\[*--noshell*\] *\[filename\]*

#### 8.11 Command-Line Options

#### The interpreter accepts the following command-line options:

Memory Management:

- *-m* \<*size*\>: Maximum in-memory table size.
- *-t* \<*size*\>: Maximum temporary variable/array memory.

Character Variables:

- *--clen* \<*length*\>: Maximum character variable length (default: 256).

Execution Control:

- *--noshell*: Disable the *SYSTEM* command and the *SHELL* function.

Input Control:

- *-u *\<filename**\>: Open the specified file as the input dataset (Equivalent to a *USE* statement).
- *--infmt*: Specify the format of the input dataset (ignored unless the *-u* option is specified).

Output Control:

- *-o*: Open the specified file for console output (Equivalent to an *OUTPUT* statement).
- *-p* \<specstr\>: Pager specification for interactive mode.
- *-q*: Suppress writing of console output to standard output (can be undone with *ECHO ON*).
- *-s*: Open the specified file as the output dataset (Equivalent to a *SAVE* statement).
- *--outfmt*: Specify the format of the output dataset (ignored unless the *-s* option is specified).

#### 8.12 Argument

The name of a script (“command file”) to run. If not specified then an interactive session is opened.

### 8.2 Case Insensitivity

The language is entirely case insensitive:

- Variable names: *TEMP*, *temp*, and *Temp* refer to same variable.
- Commands: *PRINT*, *print*, and *Print* are equivalent.
- Function names: *SIN*, *sin*, and *Sin* are equivalent.
- Keywords: *IF*, *if*, and *If* are equivalent.

**Exception:** Character string literals preserve case: - *"Hello"* and *"HELLO"* are different values.

### 8.3 Reserved Names and Keywords

Command and function names are reserved keywords in the sdata language. A column or variable whose name collides with a reserved keyword (e.g. a CSV file containing a column literally named `AS` or `USE`) can still be referenced using the backtick quoted-identifier form (see Section 3.2). When a dataset is loaded via *USE* and a column name matches a reserved keyword, sdata emits an advisory warning of the form:

> ``warning: column "AS" matches a reserved keyword; reference it as `AS` or rename it``

This warning can be suppressed with *OPTIONS WARNRESERVED NO*. Best practice remains to avoid reserved keyword names in column names when possible.

### 8.4 Error Messages

All error conditions specified in this document shall produce clear, descriptive error messages that:

- Identify the nature of the error.
- Indicate the location (line number if applicable).
- Suggest corrective action where appropriate.

### 8.5 Future Extensions

This specification notes several areas where future versions may provide additional capabilities:

- Special missing value codes for IEEE 754 infinity and NaN (*.i*, *-.i*, *.n*).
- Additional file format support.
- Numeric literals in bases other than ten.
- Enhanced formula evaluation in spreadsheets.

These extensions are noted for planning purposes but are not requirements for the initial implementation.
