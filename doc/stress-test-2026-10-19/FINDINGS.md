# SData 1.0 stress test — findings log (running)
Binary under test: sdata 0.37.0 (bin/sdata, built 2026-10-19 from main @70f41d7), sdata-core per path pin.

Severity: H = wrong data/crash on plausible input; M = spec violation or misleading failure; L = cosmetic/diagnostic.

## Findings

### F01 [H] CRLF CSV: trailing \r retained in last column (name and values)
Any CSV with CRLF line endings (OPTIONS TXTFMT AUTO, the default) yields last header `RINGS\r` and, when the
header is the type-signal, forces nothing but leaves a literal CR in the name; numeric last column values like `15\r`
are *character* (`RINGS\r$`) because "15\r" is non-numeric. Repro: `USE "/home/datasets/datasets_csv/abalone.csv"` then NAMES.
Cause: sdata_core-file_io-csv.adb streams with Ada.Text_IO.Get_Line (LF-only on Linux); only the UTF-16 path
(Split_Into_Lines) strips CR. Also bare-CR (classic Mac) files read as one header-only line (data lost, only a warning).
Spec 4.1: "Attempts auto-detection if OPTIONS TXTFMT = AUTO (default)".

### F02 [H] CSV quoted fields with embedded newlines are split into separate records
`"line1\nline2",1` -> two rows plus spurious "unclosed quote" warnings; subsequent columns shift. RFC 4180 valid input silently misparsed.

### F03 [M] Deep nesting aborts the whole session with "STORAGE_ERROR: s-intman.adb:136 explicit raise"
Thresholds (8MB stack): ~820 nested parentheses, ~390 nested IF blocks, ~555 nested FOR, ~620 nested ABS(..), ~17400-term `1+1+...`.
Spec 1.1/5.3 says no limits except stack, and "fails with error message" - message is an internal one and not recoverable.

### F04 [L] Ada runtime check messages leak (file:line) into user diagnostics
`CHR$(256)` -> "string_fns.adb:265 range check failed"; `LEFT$("abc",1e10)` -> "string_fns.adb:55 overflow check failed";
`ABS(-2^63 int)` -> "numeric_fns.adb:20 overflow check failed"; LET I% = 2**63 -> "execute_assignment.adb:170 overflow check failed".
Also stray lone "." line after "Error: Assignment failed ... ." messages.

### F05 [M] ROUND(x, n) with huge n returns NaN (a value spec says is never exposed)
`LET V = ROUND(1,400)` -> prints NaN. (n=20 fine.)

### F06 [L] 0**(-1) = Inf with IEEE_DIVIDE NO, whereas 1/0 is an error
Inconsistent with 2.4 (float division by zero fails unless IEEE_DIVIDE YES). 

### F07 — RETRACTED. I first recorded that a recursive SUBMIT exits 0; re-measured: it exits 1 (the earlier 0 was the exit status of a `| head` pipeline in my harness).

### F08 [L] BOM-less UTF-16 (LE/BE) CSV is not detected; NUL bytes are accepted into column names/values
(`A\0$`). Spec 4.1 promises UTF-16 auto-detect (BOM case works).
(F02 addendum: SAVE correctly writes embedded-newline fields quoted, but USE cannot read sdata's own output back -> round-trip loses row alignment.
 A CR inside a quoted field is silently dropped on re-read ("cr\rx" -> "crx"), same Get_Line cause as F01.)

### F09 [L] `1e309` / `-1e309` in CSV numeric column loads silently as Inf/-Inf (no overflow warning); 4.9e-324 and 1e-400 -> 0 silently.

### F10 [M] XLSX/ODS writers emit raw control characters (U+0001..U+001F except TAB/LF/CR) -> not well-formed XML
`LET S$ = "x" + CHR$(1)` then SAVE "f.xlsx" / "f.ods": sheet1.xml / content.xml fail a strict XML parse
(python xml.dom.minidom: "not well-formed (invalid token)"). Excel/LibreOffice will reject or repair such a file.
sdata's own reader tolerates it, so a round-trip test would not notice. Should drop/escape (e.g. _x0001_ in OOXML) or error.
Related (L): leading/trailing spaces in `<t>` written without xml:space="preserve" (consumers may trim).

### F11 [M] `SELECT CASE expr` (the spelling in design.md §7.1 and §5.3) is silently swallowed: no error, no case executes
Real syntax is `SELECT expr` / `CASE v:` / `END SELECT` (HELP SELECT). With the documented spelling the whole block
(through END SELECT) vanishes and nothing prints. e.g. `LET X=3 / SELECT CASE X / CASE 3 / PRINT "three" / END SELECT / RUN`
prints nothing. Either accept the keyword or reject it with a syntax error; design.md row also lacks the `SELECT expr` form.

### F12 [M] BREAK / BREAK WHEN in non-interactive mode aborts the rest of the record instead of "continuing automatically"
design.md §7.1 BREAK: "In non-interactive mode, BREAK emits a trace line to stderr and continues automatically".
Observed: statements after a triggered BREAK in the same record never run (PRINT "after" skipped on that record).
Also the trace is prefixed "[debug]" and printed even without --debug.

### F13 [L] FOR loop variable after normal termination is the last in-range value (3), not the first out-of-range value (4)
design.md §7.1 FOR row says it "retains the first out-of-range value". `FOR I = 1 TO 3 ... NEXT : PRINT I` prints 3.

### F14 [H] VAR/STD (function, AGGREGATE, STATS) use the naive sum-of-squares formula: catastrophic cancellation -> negative variance, and a crash on constant columns
Root cause: sdata_core-evaluator-aggregate_fns.adb:70,81 `(Sum_Sq - Sum**2/N)/(N-1)`.
 - `USE "const.csv"` (1055 copies of 32.86281070745698) `STATS X /STATS=N MEAN STD VAR` ->
   `Error: a-ngelfu.adb:891 instantiated at sdata_core-real_functions.ads:13` (Sqrt of tiny negative; the whole statement aborts, no table).
   Real corpus case: /home/datasets/datasets_csv/EDEMOS.CSV columns MAGE, MEDUC (a constant column) — any all-columns STATS on that file fails.
 - X = 1e9 + U(0,1), n=1000: STATS reports VAR = -1049.6 (true 0.0863) on one sample and +1968.0 on another (repro/F14_cancel.csv) — i.e. garbage of either sign. `VAR(1000000000.1,1000000000.2,1000000000.3)` = -256 (true 0.01).
 Fix: Welford / two-pass; clamp at 0.

### F15 [L] Identifiers cannot start with an underscore, but data may contain such columns (SAS `_TYPE_`, `_FREQ_`) and sdata itself emits `_NAME_$`
`STATS X ...` then `DISPLAY _NAME_$` -> `unexpected character "_"`. Backtick form works but USE emits no advisory (only for reserved words).
 Real-data corroboration: gymCOMMA.csv / GYMHCAT.CSV / gymtutorC1.csv column SEG7DIG (values ~1,000,002, n=293):
 sdata STD 0.81286 vs exact 0.81293 (4th significant digit wrong) — plain mean-shifted-by-1e6 data is enough.

### F16 [M] Blank lines inside/at the end of a CSV become phantom all-missing records (pandas/R/SAS skip them); handling is also inconsistent at EOF
`a,b / 1,2 / 3,4 / <blank> / <blank>` -> 3 records (one phantom; the final blank line is dropped, the other is not). A mid-file blank line yields a phantom
row plus a "only 1 of 2 expected fields present" warning. Real corpus case: CALL_VOLUME.CSV (2 blank lines before 2 comma-only rows) -> NMISS differs from pandas (4 vs 2).

### F17 [M] RENAME silently ignores invalid/unsupported cases and can break the name-suffix-determines-type invariant
 - `RENAME X = Y` where Y exists: spec §7.1 says it must fail; sdata prints nothing and does nothing.
 - `DROP Y` then `RENAME X = Y` (spec: legal "unless it has been DROPped"): silently does nothing (X stays X). Arguably because DROP only takes effect at the next RUN, but there is no message either way.
 - `RENAME NOPE = Q` (no such variable): silent no-op.
 - `RENAME X = X$` (numeric column -> "character" name) is accepted: column now named `X$` but still numeric (DISPLAY prints numbers; `LET W = X$ + 1` runs).
   `RENAME G$ = G` yields a numeric-named column holding strings. spec: "A numeric variable may not be assigned a character variable name and vice versa"; the USE per-dataset RENAME= rejects this correctly.
   After SAVE/USE the type changes underneath the user.

### F18 [L] `USE f /NSCAN=-5` and `/NSCAN=99999999999999999999` abort with "An error occurred: CONSTRAINT_ERROR: bad input for 'Value: ..." (unhandled Ada exception text).

### F19 [M] WIF (Weibull quantile) has scale/shape reversed relative to WCF/WDF/WRN and its own HELP
`WIF(0.5,2,3)` = 2.4977 but `WCF(WIF(0.5,2,3),2,3)` = 0.857 (should be 0.5). `WIF(0.5,3,2)` = 1.76999 = the correct WIF(0.5, scale=2, shape=3).
Also design.md describes WIF as a "probability density".

### F20 [L] design.md function table disagrees with the implementation on distribution arities
design.md: GCF/GDF/GIF(x, p) (shape only), ECF/EDF/EIF(x) (no parameter). Implementation + HELP: GCF(x,shape,rate), ECF(x,rate), etc. -> `GCF(3,2)`: "expects 3 argument(s), got 2".
(Per CLAUDE.md design.md wins; so either impl or spec needs to change before 1.0.)

### F21 [L] Quantile accuracy: TIF(0.5,3) = -1.5e-8 (exact 0); XIF(1e-6,5) relative error 5e-9 (bisection tolerance). Other ~150 distribution probes (Z/X/T/F/B/N/P/L/LTW incl. tails) agree with scipy to 1e-9.

### F22 [H] NRN(n, p) — documented binomial random variate — returns a *normal* variate N(mean=n, sd=p)
200,000 draws of `NRN(20, 0.3)`: mean 19.9996, sd 0.300 (non-integer values, max 21.35). Binomial(20,0.3) is mean 6, sd 2.05.
`MRN(20,0.3)` (documented as a synonym) is correct (integers, mean ~6). Cause: sdata_core-evaluator-distrib_fns.adb Handle_NRN calls Statistics.Normal_RN
instead of Binomial_RN (copy of Handle_ZRN). All other RNGs (RAN/URN/ZRN/ERN/GRN/BRN/TRN/FRN/XRN/WRN/LRN/PRN/MRN) match theoretical mean/sd to 3 digits over 200k draws.

### F23 [L] Distribution boundary / precision oddities
 - `XDF(0,2)` = 0 (exact 0.5) and `XDF(0,1)` = 0 (exact +Inf): density at the x=0 boundary wrong for df<=2.
 - `BDF(0,0.5,0.5)` -> "a-ngelfu.adb:99 explicit raise" (leaked Ada text; 0**negative) instead of Inf/domain message.
 - `NDF(2.5,10,0.5)` = 0.0439 for non-integer k (NCF/PCF floor k; NDF should be 0 or an error).
 - `TDF(0,1e10)` = 0.398942058 vs 0.398942280 (rel err 5.6e-7; lgamma difference cancellation for huge df).

### F24 [H] CSV lines longer than 1 MiB are silently split into several lines (header truncated, each data row becomes multiple records)
sdata_core-file_io-csv.adb:183 `Max_Line : constant := 1_048_576` + Ada.Text_IO.Get_Line(Line_Buf) -> a line over 1,048,576 bytes is returned in 1 MiB pieces.
 - synthetic: 200,000 columns named C0.. -> header truncated to 144,961 columns, data rows reported as "only 55040 of 144961 expected fields".
 - corpus: /home/datasets/datasets_csv/RANDOMWIDE1X.CSV (100,000 numeric columns, 9 data rows of ~1.8 MB): pandas = 9 rows x 100,001 cols;
   sdata = 100001 *records* (the header alone is 688 KB; each row 1.8 MB is cut at 1 MiB), STATS on SEQ -> N=18, mean 3.6e8 vs N=9, mean 4.
 Only warnings are emitted; USE proceeds, so downstream results are garbage. Should raise a hard error (or lift the limit).

### F25 [H] Character functions are byte-oriented: UCASE$/LCASE$ corrupt valid UTF-8; LEN/LEFT$/RIGHT$/MID$/INDEX count and cut bytes
Input CSV (valid UTF-8) `ÀÉ, Ångström, straße, 日本語` through `LET L$ = LCASE$(NAME$)`, `LET U$ = UCASE$(NAME$)`, SAVE:
 - `LCASE$("ÀÉ")` -> bytes C3 80 -> E3 80 / E3 89 (each byte lower-cased as Latin-1): invalid UTF-8 in the output file.
 - `UCASE$("日本語")` -> `Ɨ�Ɯ�Ȫ�` (silently mangled), `UCASE$("straße")` -> `STRAßE`, `LCASE$("Ångström")` -> `�ngstr�m`.
 - `LEN("é日本")` = 8 (bytes); `LEFT$("日本語",1)` -> one invalid byte; MID$/RIGHT$ likewise.
 - consequently `--clen N` truncation can also cut a code point in half (not tested separately).
Spec 4.1 promises UTF-8 as a portable CSV charset, so a program can read, transform and write text that is no longer valid UTF-8.
Suggest: make the functions code-point aware (or ASCII-only case mapping + documented byte semantics, at least never touching bytes >= 0x80).

### F26 [L] HEX$/BIN$/OCT$ second (width) argument documented in design.md but rejected: "function 'HEX$' expects 1 argument(s), got 2"

### F27 [L] CLI: unknown options are silently ignored (`sdata --nosuch x.cmd`, `-z` -> runs normally, exit 0); extra positional arguments ignored;
`sdata /tmp` (a directory) -> "An error occurred: ADA.IO_EXCEPTIONS.DEVICE_ERROR: Is a directory". `-o`/`-u`/`-s` with a script name as value silently overwrite it (user error, but `-o` truncates without any overwrite guard).

### F28 [M] REPEAT 0 generates one record, not zero
`REPEAT 0 / LET X = 1 / RUN` -> "RUN complete. 1 records and 1 variables processed." (REPEAT -1 and non-numeric are rejected with a clear message.)
Also `REPEAT 2.7` and `REPEAT 99999999999999999999` -> "An error occurred: CONSTRAINT_ERROR: bad input for 'Value: ..." (same unhandled-exception pattern as F18, `Integer'Value` on the literal).

### F29 [M] Column names longer than 64 characters are silently truncated, so distinct long names collide and columns are lost
Header `A*70+"1", A*70+"2", A*70+"3"` -> one column of 64 `A`s holding only the last column's values (two "duplicate column name" warnings, quoting the truncated name).
No warning that truncation happened; the same would hit any SAS-style long names that differ only in a suffix.

### F30 [L] SYSTEM: not as documented
 - design.md: "If the command is not quoted it is taken as the name of a variable or expression." `SET C$="echo hi"` / `SYSTEM C$` -> "timeout: failed to run command 'C$'" (runs the literal token); `SYSTEM 5` same.
 - Commands without shell metacharacters are exec'd directly via `timeout`, so shell builtins fail: `SYSTEM "exit 7"`, `SYSTEM "cd /tmp"` -> "timeout: failed to run command 'cd': No such file or directory" (while `SYSTEM "echo $HOME"` works).
 - With `OPTIONS SHELLTIMEOUT 1`, `SYSTEM "sleep 5; echo done"` returns after 1 s but still prints "done" (only the sleep is killed, no "timed out" message), whereas `SYSTEM "sleep 5"` correctly reports "timed out after 1 seconds".
 - Untrusted input is not shell-interpolated anywhere I could find (`USE "x; touch pwned"` is treated as a file name).

### F31 [M] /FMT= does not override the file extension on SAVE (spec §4.4: "Format may be specified explicitly with FMT ... overriding extension-based detection")
 - `SAVE "o4.csv" /FMT=ODF` -> a CSV file; `SAVE "o5.xlsx" /FMT=ODF` -> an XLSX (extension wins); `SAVE "o6" /FMT=MSEXCEL` -> "o6.CSV" (default .CSV appended first, FMT ignored).
 - Only the "unrecognised extension" case works (`SAVE "o3.dat" /FMT=OOXML` -> real xlsx).
 - Reading it back without /FMT treats the zip as CSV and DISPLAYs binary garbage with a single warning (no binary/NUL detection).

### F32 [L] Invalid option values are silently accepted
`OPTIONS HEADER MAYBE` (silently behaves as HEADER NO: the data's header row becomes data, columns COL1$..), `OPTIONS TXTFMT XYZ`, `OPTIONS CHARSET NOPE`,
`OPTIONS IEEE_DIVIDE 2`, `OPTIONS CSVDLM ""`, `OPTIONS DEBUG 99`, `USE f /FMT=BOGUS`, `USE f /CHARSET=BOGUS`, `USE f /DLM=""`, `SAVE f /CHARSET=BOGUS`, `/HEADER=MAYBE`, `/DLM=""`, `OUTPUT /BOGUS`
(whereas `USE f /NOSUCH=5`, `TABLES G$ /BOGUS`, `OPTIONS MAXINTAB abc` are properly rejected). Negative numbers in OPTIONS give "syntax error: unexpected "1"" (OPTIONS MAXINTAB -1).
Spec 4.1 says an invalid character set "fails with error message".

### F33 [L] More lenient-where-it-should-fail cases
 - `LET 5 = 5` creates a permanent column literally named `5`.
 - `DISPLAY NOSUCH` prints a column of missing values for a nonexistent variable (no error); `WRITE NOSUCH`, `HOLD NOSUCH` accepted silently (until RUN).
 - Raw `CONSTRAINT_ERROR: bad input for 'Value:` on: `DIGITS -1|3.5|abc|<huge>|(none)`, `USE f /SKIP=-1`, `/MAXROWS=-1` (extends F18/F28); `RSEED 99999999999999999999` -> "execute_declarative.adb:326 overflow check failed".
 - `DIGITS 1000` silently falls back to E-notation output.

### F34 [H] ODS reader: a row with `table:number-rows-repeated` > 1000 silently terminates the read of the whole sheet
sdata_core-file_io-odf.adb:361 `exit when Row_Repeat_Count > 1000;` is meant to skip trailing empty padding (LibreOffice emits 1048576), but it also fires for *data* rows and exits the
row loop, dropping that row **and every row after it**. Repro (o_gap.ods): header; row `7`; row `0` repeated 2000x; row `9` -> sdata loads only `7`.
LibreOffice writes runs of identical rows exactly this way. No warning. (Counts <= 1000 expand correctly; identical-row runs and empty-row padding should be distinguished by cell content, and a truncated read must at least warn.)

### F35 [L] SAVE to XLSX/ODS happily writes beyond Excel's grid (16,384 columns -> cell refs XFE1, XFR1..., >1,048,576 rows) with no warning; Excel will refuse such files.

### F36 [M] Colon ranges (`X1:X3`, design §3.6) are silently mis-handled outside KEEP/DROP/ARRAY/DISPLAY — wrong results, no error
With columns X1..X4,Y and rows (1,2,3,4,9),(5,6,7,8,9):
 - `LET S = SUM(X1:X3)` -> S = 1 and 5 (X1 only; expected 6 and 18). `MEAN(X1:X3)`, `N(X1:X3)`, `MAX(X1:X3)` likewise = X1.  (`SUM(AR)` with `ARRAY AR X1:X3` is correct.)
 - `STATS X1:X3` analyses only X1 (silently); `TRANSPOSE /KEEP=X1:X3` transposes only X1; `BY X1:X2` and even the dash form `BY G1-G2` silently group by the first variable only (verified: with G1,G2,V rows (1,1),(1,2),(1,2),(2,1) `BY G1:G2` + `AGGREGATE` yields 2 groups instead of 3; `BY G1 G2` gives 3).
 - `TABLES X1:X2` -> `Unrecognized command "X2"`; `AGGREGATE S = SUM(X1:X3)` -> "expected ')' to close 'SUM('".
 (the dash form `X1-X3` works in DISPLAY/KEEP/DROP/SORT/ARRAY; in an expression it is subtraction, as it must be.)
Also (L): `ARRAY AR A1 B1$` mixes numeric and character members without error although design §7.1 requires one type;
`LET IF = 1` creates a variable named with a reserved word without needing backticks.
(F02 independent confirmation: the public csv-spectrum suite (github.com/max-mapper/csv-spectrum, 11 cases, expected JSON): 8/11 pass;
 `newlines`, `newlines_crlf`, `quotes_and_newlines` fail — every case with a newline inside a quoted field. Script: tools/csvspectrum.py)

### F37 [H] XLSX reader ignores cell references (`r="B3"`): a row with an omitted (blank) cell has its remaining cells shifted left -> silent data corruption
sdata's own XLSX writer omits blank cells (valid OOXML; Excel does the same), so any SAVE of a table with a missing value followed by USE of that file misaligns the row.
Repro: `m.csv` = `a,b / 1,2 / ,3 / 4, / 5,6`; `USE m.csv; SAVE "m.xlsx"; RUN; USE "m.xlsx"; DISPLAY` -> row 2 reads (3, .) instead of (., 3); row 3 reads (4,.) correct only by luck.
Sheet XML written: `<row r="3"><c r="B3"><v>3</v></c></row>` -> reader assigns the first `<c>` to column A. Titanic (public seaborn copy): `age` missing at row 6 became 0.0 / shifted columns after an xlsx round trip.
(ODS round trip is fine: it uses explicit repeated empty cells.) Check also: files exported from Excel with blank cells.
 Independent confirmation with openpyxl (Excel-compatible writer): rows [a,1,2],[b,<blank>,3],[<blank>,4,5],[d,6,<blank>] read as
 (a,1,2) (b,3,.) ("4"?!,5,.) (d,6,.) — NAME$ = "4" (a number landed in the character column). Excel/openpyxl omit blank cells, so real workbooks with gaps are corrupted.

### F38 [H] A zero-row table runs the data step once: a phantom all-missing record is created (and SAVEd)
 - header-only CSV: `USE "hdr_only.csv"` (a,b,c; no data) `LET Z = 1 / SAVE "ho.csv" / RUN` -> "RUN complete. 1 records"; ho.csv = `A,B,C,Z` / `,,,1`.
 - empty /JOIN result (no matching keys) -> same: RUN processes 1 record and SAVE writes a `,,` row.
 - (a SELECT that filters everything out correctly gives 0 records; so does `REPEAT n`>0). Same root as F28 (REPEAT 0 => 1 record): the loop is entered once for an empty table.
 Effect: any pipeline that filters/joins to nothing emits a bogus row instead of an empty file.
 Cause: sdata_core-file_io-ooxml.adb ~426-431 advances `Col_Idx := Col_Idx + 1` per `<c>` element and never reads the `r` attribute (the same loop is used for type inference and data load).
 Related (spec-sanctioned but lossy): OOXML/ODF infer a column's type from the first data row only, so a numeric column whose first cell is blank becomes character
 (e.g. corpus AOROTOBI.CSV through an xlsx round-trip turns QUESTCD, SEXCD, DIABCD ... into `QUESTCD$` ...).

### F40 [L] Lexer caps any token (incl. a string literal) at 1024 characters: `Error: token longer than 1024 characters`
Independent of `--clen` (so `--clen 5000` still cannot build a 2000-char literal in a script; strings must come from data).

### F41 [M] Disk-spill mode is catastrophically slow on wide data
ADOLFO.CSV (15,029 rows x ~1,300 cols ≈ 19.5 M cells, 40 MB): `USE; STATS /NOPRINT` in memory = 30 s / 341 MB RSS.
The same with `OPTIONS MAXINTAB 100000` (forces the SQLite spill path) had not finished after ~24 min wall / ~14 min CPU (RSS flat at 84 MB; no progress output) and was killed — at least 30x slower.
While spilling, a `GNAT-TEMP-000001.TMP` file (194 MB) is created in the *current directory* (not $TMPDIR) — it was still there when the process ended abnormally (the harness cleaned it up).

### F42 [H] Integer (`%`) CSV columns are parsed through a double: large integers are silently rounded, and values near the int64 limits are rejected
Spec §2.2/2.3: 64-bit integers, exact. File `I%` column: `9007199254740993` -> loaded 9007199254740992; `1234567890123456789` -> 1234567890123457024 (and SAVEd that way);
`5000000000000000001` -> 5000000000000000000; `9223372036854775806`, `9223372036854775807`, `-9223372036854775807`, `-9223372036854775808` and even `9223372036854775000`
-> "out of integer range -- stored as missing" (the Real->Integer conversion overflows), although `LET K% = 9223372036854775807` in a script is exact.
No warning for the silent rounding. 64-bit identifiers (order ids, snowflake ids, account numbers) are the real-world victims. Unsuffixed columns holding such ids are floats by design but also print/save with lost digits.
Also (L): `STD`/`VAR` of values around 1e155+ overflow in the sum of squares -> "Result is not a number (NaN)" aborts the whole AGGREGATE/STATS statement (same root as F14).

### F43 [L] A UTF-8 BOM at the start of a script file (Windows editors) is not skipped: `Error: Unrecognized command "<EF BB BF>REPEAT"`; CSV input handles the BOM, scripts do not.

### F44 [L] Interactive REPL: Ctrl-C (SIGINT) always terminates the whole interpreter (exit 130), at the idle prompt as well as during a RUN
It does not cancel the running statement and return to the prompt, so a stray Ctrl-C (or the natural reaction to a runaway `WHILE`) discards the in-memory table and the queued program.
(Batch mode: SIGINT/SIGTERM/SIGHUP all terminate promptly, including inside a tight `WHILE 1` loop — good. Ctrl-D at the prompt exits cleanly.)

### F45 [M] AND / OR do not short-circuit, so the usual guard idiom fails
`LET X = 0 / IF X <> 0 AND 1/X > 1 THEN PRINT "yes"` -> `Error: Division by zero.`; `IF X = 0 OR 1/X > 1 THEN ...` -> same error.
(The three-argument function `IF(X = 0, 1, 1/X)` does evaluate lazily and works.) Spec is silent; at minimum document it, ideally evaluate lazily like IF().

### F46 [M] Character-set handling is mostly a no-op (spec §4.1 / §4.5)
 - Invalid UTF-8 is never rejected: `csv/badutf8.csv` (bytes FF FE FD, C3 28) loads silently, also with an explicit `/CHARSET=UTF-8`. Spec: "Invalid characters for detected/specified charset: operation fails with error message".
 - `/CHARSET=LATIN1 | WINDOWS-1252 | CP1252` are accepted but nothing is transcoded: reading a Latin-1 file and `SAVE ... /CHARSET=UTF-8` writes the raw byte 0xE9 again (output is still Latin-1/invalid UTF-8). Unknown names (`BOGUS`) are accepted too (F32).
 - `/CHARSET=ISO-8859-1` (unquoted, with hyphens) -> `syntax error: unexpected "-"`; `/CHARSET=UTF-16` on a non-UTF-16 file -> "Ada.Strings.UTF_Encoding.To_UTF_16: UTF-16BE/LE string has odd length" (internal text).
 - Characters not representable on output (spec: SAVE fails) cannot be exercised because no narrower charset is implemented except ASCII, which is enforced (`non-ASCII byte (value 233) in input -- rejected (CHARSET=ASCII)` — good).

### F47 [M] Large (> MAXINTAB) CSV: memory is not bounded by the cell limit and the run does not finish in reasonable time
CL10S6LT.CSV (432 MB, 438 columns, ~175 M cells; default OPTIONS MAXINTAB = 50,000,000): `USE` took ~2 min and left an 825 MB `GNAT-TEMP-000001.TMP` in the current directory;
the following `STATS /NOPRINT` ran 5+ more minutes with RSS climbing to 5.1 GB (machine has 7.9 GB; "available" fell to 1.2 GB) and had not finished after 7.5 min when stopped.
So the documented "max in-memory table size" does not cap RSS (the spill store apparently holds/caches far more), and a modest-size real-world file can exhaust a 8 GB workstation. (pandas loads the same file in ~30-60 s.)

### F48 [M] Integral-valued E-notation literals are typed as 64-bit *integers*, so scientific notation overflows instead of promoting to float
`PRINT 1e10 * 1e10` -> `Error: Integer overflow in OP_MUL` (also `1e18 * 10`, `2e9 * 5e9 * 1e9`); `1e300 * 1e300` -> Inf; `1.5E3` is float, `1e3` prints `1000` (integer), `1e0` prints `1`.
Spec §3.6 lists "integers, floating point numbers, or E notation" as separate literal kinds; a user writing 1e10 expects a float. Only literals too large for int64 (1e19) become floats.

### F49 [L] `.5e3` is lexed as `.5` followed by the identifier `e3` ("undefined variable e3") — an exponent is not accepted after a leading-dot decimal (`5.e2`, `1.5E3`, `3.e-2` work). `1.2.3` -> raw `CONSTRAINT_ERROR: bad input for 'Value: "1.2.3"` (F18 family).

### F50 [H] STATS and AGGREGATE crash (stack overflow) when a group / the whole table has >= ~350,000 rows
Any whole-table `STATS` (even `/STATS=N`) or un-BY'd `AGGREGATE`, and any `BY` group of that size, dies with `Error: s-intman.adb:136 explicit raise` (a SIGSEGV turned into Storage_Error), no result table.
Bisected on a 2-column numeric CSV: 300,000 rows OK, 350,000-400,000 fails; 1,000,000 rows with a single BY group fails; `BY` with 7 groups of 143k rows each works; SORT, TABLES, TRANSPOSE, DISPLAY work at 1M rows.
Same for MEDIAN/PCTL/N/MEAN/STD. Running under `ulimit -s unlimited` makes it succeed, so the per-group data is held on the 8 MB default stack.
Real corpus case: /home/datasets/datasets_csv/246-W2.CSV (455,549 rows x 10 cols): `STATS rate` -> crash. The first sweep missed it because it only covered files < 20 MB.
Repro: repro/F50_gen.py then repro/F50.cmd.
 F01 corpus evidence for the bare-CR case: customer_cln_c.csv (48.8 MB, 323,960 records separated by lone CR) is one 48 MB "line" to sdata: the 1 MiB header chunk becomes ~67,772 junk columns
 (warnings "duplicate column name 1$ / 0 / 5$ ..." — data values used as names); STATS then reports CASEID N=31 instead of 323,960. pandas reads it correctly.
 Mac-style CR and mixed endings are within "TXTFMT AUTO" per spec §4.1; at minimum a one-line file this size should be an error.
 F50 addendum: `BY G` + AGGREGATE crashes whenever the *largest group* is that big (4,000,000 rows / 7 groups = 571k per group: crash; 2,000,000 rows / 7 groups = 286k: ok).
 Also HUGE11M.CSV (11,000,001 rows x 3 cols = 33 M cells, loads in ~50 s / 1.8 GB RSS): `DISPLAY /FIRST=2 /LAST=2` -> `Error: s-intman.adb:136 explicit raise`
 (DISPLAY /FIRST,/LAST works at 4,000,000 rows, so a second, higher stack/size limit exists on the DISPLAY path).

### F51 [M] OUTPUT ignores its /CHARSET= and /FMT= options (design §6.1, §7.1 OUTPUT)
`OUTPUT "ou" /CHARSET=UTF-16 /FMT=CRLF` then PRINTs: ou.DAT is plain UTF-8 with LF line endings (file(1): "Unicode text, UTF-8"; no BOM, no CR).
`OUTPUT "ou8" /CHARSET=ASCII` + `PRINT "héllo"` writes the non-ASCII bytes unchanged (spec: unrepresentable characters must fail; SAVE/USE do enforce ASCII, OUTPUT does not).
Also the `RUN complete...` status line is written into the OUTPUT file along with PRINT output (probably intended).

### F52 [M] Function fuzz (175 registered functions x a 15-value extreme-argument grid, 21,785 calls; `tools/fnfuzz.py`, `tools/fnfuzz2.py`)
Three recurring defect classes beyond the ones listed above:
 1. **Hangs (CPU-bound, no error, no iteration cap)** when a distribution parameter violates its documented domain:
    `TCF(1,-1)` (still running after 60 s), `TCF(-1,-1)`, `TIF(0.5,-1)`, `BCF(0.5,-1,0)`, `BIF(-1,-1,-1)` (16 of 64 grid points hang), `FCF(0.5,-1,0.5)` (7 of 64), `FIF(0.5,-1,-1)`.
    (`ZCF(1,0,-1)` correctly reports "Standard deviation must be positive", `XIF/GIF/NIF/PIF/ZIF` never hung.) A negative df typed in a data step freezes the run.
 2. **NaN values escape** (spec §2.4: NaN is "never exposed as a value"): `COSD/SIND/TAND(1e308)`, `LTW(1e308)`, `ROUND(x, n)` for n >= 1e15 (44 of 121 grid points),
    `NCF/NDF/MDF(x, 1e308, p)`, `XCF(1,1e-308)`, `XDF/PDF/GDF` with 1e308 parameters, `TCF(0,0)`, `BCF(0.5,0,0)`, `FCF(0.5,0,0)`, `GIF(0.5,0,0)`, `BIF(-1,0,0)`.
 3. **Ada runtime text instead of a domain message** (`... .adb:NNN overflow check failed / explicit raise / instantiated at ...`): ABS(MININT), ATAN2/ATAN2D (a-ngelfu.adb:394), BDF/WDF (a-ngelfu.adb:99),
    COSH/SINH/HCS/HSN/HTN (a-ngelfu.adb:684), FDF/GIF/TDF/XIF (a-ngelfu.adb:92/891, gamma_function.adb:175), GCF (741), HEX, INSTR/POS/MATCH, MIF/NIF/PCF (statistics.adb:578/371), TRUNCATE (misc_fns.adb:181), CHR$, LEFT$.
 `STD/VAR` of 2-3 huge arguments -> "Result is not a number (NaN)" (overflow of the squared terms; same root as F14).
