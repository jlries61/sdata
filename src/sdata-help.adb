--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

with Ada.Characters.Handling; use Ada.Characters.Handling;
with SData.IO;                use SData.IO;

package body SData.Help is

   -- ==========================================================================
   --  Index (bare HELP)
   -- ==========================================================================

   procedure Help_Index is
   begin
      Put_Line ("Available Commands:");
      Put_Line ("  Data:        USE, SAVE, RUN, NEW, NAMES, WRITE, DELETE, DISPLAY");
      Put_Line ("  Variables:   LET, SET, UNSET, HOLD, UNHOLD, KEEP, DROP, RENAME");
      Put_Line ("  Arrays:      ARRAY, DIM");
      Put_Line ("  Control:     IF, SELECT CASE, FOR, WHILE, REPEAT, BREAK");
      Put_Line ("  Data step:   SELECT (filter), SELECT /ALL, BY, SORT, REPEAT");
      Put_Line ("  Output:      PRINT, OUTPUT, ECHO, DIGITS");
      Put_Line ("  Files/paths: FPATH");
      Put_Line ("  Session:     RSEED, SYSTEM, SUBMIT, HELP, OPTIONS, QUIT, END");
      Put_Line ("  Debugger:    BREAK, BREAK WHEN  (see also: HELP DEBUGGER for --debug mode)");
      New_Line;
      Put_Line ("Available Functions:");
      Put_Line ("  Math:        ABS, SQRT/SQR, LOG/LN/LOGE, LOG2, LOG10/CLG/LGT, EXP,");
      Put_Line ("               ROUND, CEIL, FLOOR, INT, FIX/IP, FP/FRAC, MOD, SGN,");
      Put_Line ("               TRUNCATE, PI, LTW");
      Put_Line ("  Trig (rad):  SIN, COS, TAN, ATN/ARCTAN, ATAN2, ARCSIN, ARCCOS,");
      Put_Line ("               COT, CSC, SEC, SINH/HSN, COSH/HCS, TANH/HTN, DEG/DEGREE,");
      Put_Line ("               RAD/RADIAN");
      Put_Line ("  Trig (deg):  SIND, COSD, TAND, ATND, ATAN2D");
      Put_Line ("  String:      LEN, LEFT$, RIGHT$, MID$, SEG$, TRIM$, LTRIM$, RTRIM$,");
      Put_Line ("               UCASE$/UPPER$, LCASE$/LOWER$, POS, INSTR, INDEX, MATCH,");
      Put_Line ("               CHR$, ASCII/ASC, STR$, VAL, NUM$, MAXLEN");
      Put_Line ("  Conversion:  NUM, HEX, HEX$, OCT$, BIN$");
      Put_Line ("  Arrays:      LBOUND, UBOUND");
      Put_Line ("  Record:      RECNO, BOF, EOF, BOG, EOG, LAG, LAGC$, NEXT, NEXTC$, OBS, OBSC$");
      Put_Line ("  Special:     MISSING, INF, NMISS, RAN/RANDOM/RND, DATE$, TIME$, TIMER, SHELL,");
      Put_Line ("               FALSE, TRUE, ERR, ERL,");
      Put_Line ("               MAXINT, MININT, MAXNUM, MINNUM, MAXLVL");
      Put_Line ("  Aggregate:   SUM, MEAN, GMEAN, HMEAN, STD, VAR, MIN, MAX, MEDIAN, N, NMISS");
      Put_Line ("  Stat PDF:    ZDF, NDF, UDF, EDF, BDF, PDF, GDF, XDF, TDF, FDF,");
      Put_Line ("               MDF, WDF, LDF");
      Put_Line ("  Stat CDF:    ZCF, NCF, UCF, ECF, BCF, PCF, GCF, XCF, TCF, FCF,");
      Put_Line ("               MCF, WCF, LCF");
      Put_Line ("  Stat IDF:    ZIF, NIF, UIF, EIF, BIF, GIF, XIF, TIF, FIF, WIF,");
      Put_Line ("               LIF, PIF");
      Put_Line ("  Stat RN:     ZRN, NRN, URN, ERN, PRN, GRN, MRN, XRN, TRN,");
      Put_Line ("               FRN, WRN, LRN, RAN, RANDOM");
      Put_Line ("  (Use HELP DISTRIBUTIONS for an overview of naming conventions.)");
      New_Line;
      Put_Line ("Use HELP <name> for details.  Use HELP /ALL for the full reference.");
      Put_Line ("Use HELP EXECUTION for an explanation of the three execution tiers.");
      Put_Line ("Use HELP CONCEPTS for an introduction to the PDV, LET/SET, and BY groups.");
   end Help_Index;

   -- ==========================================================================
   --  Commands
   -- ==========================================================================

   procedure Help_USE is
   begin
      Put_Line ("Command: USE [MOCK | ""filename[sheet]""] [/FMT=format] [/NSCAN=n]");
      Put_Line ("Loads a dataset from CSV, ODF, or OOXML files into the Data Table.");
      Put_Line ("USE MOCK generates synthetic test data.");
      Put_Line ("Sheet selection (ODF/OOXML only):");
      Put_Line ("  Append the sheet name in brackets inside the filename string.");
      Put_Line ("  The name is case-sensitive and must match the tab label exactly.");
      Put_Line ("  If omitted or not found, the first sheet is used.");
      Put_Line ("  Example:  USE ""sales.xlsx[Q2]""");
      Put_Line ("Options:");
      Put_Line ("  /FMT=format  Specifies the file format (CSV, ODF, OOXML).");
      Put_Line ("               Default is auto-detected from file extension.");
      Put_Line ("  /NSCAN=n     Number of rows to scan for type detection (default: 20).");
      Put_Line ("Formula cells (ODF/OOXML):");
      Put_Line ("  sdata has no built-in formula evaluator.");
      Put_Line ("  If LibreOffice (soffice) is on PATH, it is invoked to recalculate");
      Put_Line ("  formulas before import.  Otherwise cached values from the last save");
      Put_Line ("  are used -- correct for normally-saved files, but potentially stale");
      Put_Line ("  for volatile functions (TODAY, NOW, RAND) or manual-recalc files.");
      Put_Line ("Execution: Immediate -- loads the dataset at once.");
   end Help_USE;

   procedure Help_SAVE is
   begin
      Put_Line ("Command: SAVE ""filename[sheet]"" [/FMT=format] [/HEADER=YES|NO]");
      Put_Line ("Queues the current Data Table to be saved after the next RUN command.");
      Put_Line ("Sheet selection (ODF/OOXML only):");
      Put_Line ("  Append the sheet name in brackets inside the filename string.");
      Put_Line ("  Default sheet name: ""Sheet1"".");
      Put_Line ("  Example:  SAVE ""results.xlsx[Summary]""");
      Put_Line ("Options:");
      Put_Line ("  /FMT=format  Specifies the output format (CSV, ODF, OOXML).");
      Put_Line ("               Default is auto-detected from file extension.");
      Put_Line ("  /HEADER=val  Whether to write a header row (YES or NO). Default: YES.");
      Put_Line ("Execution: Declarative -- the file is written at the end of the next RUN.");
   end Help_SAVE;

   procedure Help_WRITE is
   begin
      Put_Line ("Command: WRITE");
      Put_Line ("Explicitly writes the current PDV record to the output table.");
      Put_Line ("Suppresses the automatic end-of-step write for that record.");
      Put_Line ("Execution: Deferred -- executed once per record inside the data step.");
   end Help_WRITE;

   procedure Help_SUBMIT is
   begin
      Put_Line ("Command: SUBMIT ""filename""");
      Put_Line ("Executes commands from an external script file. Default extension: .CMD.");
      Put_Line ("Provides cycle detection to prevent recursive submission.");
      Put_Line ("Disabled by --nosubmit flag.");
      Put_Line ("Execution: Immediate -- the script is run at once.");
   end Help_SUBMIT;

   procedure Help_SYSTEM is
   begin
      Put_Line ("Command: SYSTEM ""command""");
      Put_Line ("Executes an external shell command. Disabled by --noshell.");
      Put_Line ("Uses /bin/sh on POSIX systems to avoid profile script side-effects.");
      Put_Line ("A timeout is applied when OPTIONS SHELLTIMEOUT > 0 (requires timeout(1) on PATH).");
      Put_Line ("If the command exceeds the timeout, Script_Error is raised.");
      Put_Line ("Default timeout: 300 s in batch mode, 0 (unlimited) in interactive mode.");
      Put_Line ("Override at startup with --shell-timeout=N; override at runtime with OPTIONS SHELLTIMEOUT N.");
      Put_Line ("Execution: Immediate -- the shell command is launched at once.");
   end Help_SYSTEM;

   procedure Help_PRINT is
   begin
      Put_Line ("Command: PRINT [expr [[,] | [;] expr] ...]");
      Put_Line ("Outputs values to the console, separated by spaces.");
      Put_Line ("No arguments: Prints all permanent variables for the current record.");
      Put_Line ("Execution: Deferred -- executed once per record inside the data step.");
   end Help_PRINT;

   procedure Help_RUN is
   begin
      Put_Line ("Command: RUN");
      Put_Line ("Triggers the execution of the Data Step and any deferred SAVE operations.");
      Put_Line ("Execution: Immediate -- triggers the data step at once.");
   end Help_RUN;

   procedure Help_LET is
   begin
      Put_Line ("Command: LET variable = expression");
      Put_Line ("Creates a permanent column in the table or updates an existing one.");
      Put_Line ("Execution: Deferred -- executed once per record inside the data step.");
   end Help_LET;

   procedure Help_SET is
   begin
      Put_Line ("Command: SET variable = expression");
      Put_Line ("Creates a session variable not written to the output table.");
      Put_Line ("SET variables are not reset between records and persist across RUN calls.");
      Put_Line ("They are removed by UNSET or NEW, or when the session ends.");
      Put_Line ("Execution: Deferred -- executed once per record inside the data step.");
   end Help_SET;

   procedure Help_UNSET is
   begin
      Put_Line ("Command: UNSET variable(s)");
      Put_Line ("Removes one or more session variables from memory.");
      Put_Line ("Execution: Immediate -- takes effect at once.");
   end Help_UNSET;

   procedure Help_ARRAY is
   begin
      Put_Line ("Command: ARRAY array_name variable(s)");
      Put_Line ("Creates a virtual array providing indexed access to existing variables.");
      Put_Line ("Execution: Deferred -- executed once per record inside the data step.");
   end Help_ARRAY;

   procedure Help_DIM is
   begin
      Put_Line ("Command: DIM <arrayname> (<lower> [TO <upper>]) [/TEMP]");
      Put_Line ("Creates a permanent or temporary array (real variables).");
      Put_Line ("Elements are initialized to missing. /TEMP makes it temporary.");
      Put_Line ("A DIM statement that references an existing variable or array shall fail.");
      Put_Line ("Execution: Deferred -- executed once per record inside the data step.");
   end Help_DIM;

   procedure Help_BY is
   begin
      Put_Line ("Command: BY variable(s)  |  BY");
      Put_Line ("Groups data by the named variables for the next RUN.");
      Put_Line ("Sets BOG/EOG indicators and makes BY-group boundaries visible to");
      Put_Line ("LAG, NEXT, and BOG/EOG functions.");
      Put_Line ("Bare BY (no variables) cancels the active grouping.");
      Put_Line ("Execution: Declarative -- grouping is active for all subsequent RUNs.");
   end Help_BY;

   procedure Help_VANDALIZE is
   begin
      Put_Line ("Command: VANDALIZE <source> INTO <dest>");
      Put_Line ("         [/PERTURB[=<prob>[,<sd-frac>]]]");
      Put_Line ("         [/SHUFFLE[=<prob>]]");
      Put_Line ("         [/MISS[=<prob>]]");
      Put_Line ("         [/BY=<var>[,<var>...]]");
      Put_Line ("Creates a noisy copy of a variable by applying one or more degradation");
      Put_Line ("operations.  Source and destination may be the same variable (in-place).");
      Put_Line ("DIM array base names are supported as source and destination.");
      New_Line;
      Put_Line ("Options:");
      Put_Line ("  /MISS[=prob]");
      Put_Line ("    Set the destination to missing with probability prob.");
      Put_Line ("    Default prob: 0.05.");
      New_Line;
      Put_Line ("  /SHUFFLE[=prob]");
      Put_Line ("    Replace the destination with a value drawn uniformly at random");
      Put_Line ("    from the same column (within the active BY group if /BY is set).");
      Put_Line ("    Default prob: 1.0.");
      New_Line;
      Put_Line ("  /PERTURB[=prob[,sd-frac]]");
      Put_Line ("    Add Gaussian noise: mean 0, SD = sd-frac * column_SD.");
      Put_Line ("    Requires a numeric (float) variable.");
      Put_Line ("    Default prob: 1.0.  Default sd-frac: 0.01.");
      New_Line;
      Put_Line ("  /BY=var[,var...]");
      Put_Line ("    Stratify all operations by the named grouping variables.");
      Put_Line ("    Each group is treated independently (statistics and random");
      Put_Line ("    draws are confined to records within the same group).");
      New_Line;
      Put_Line ("Notes:");
      Put_Line ("  At least one operation (/MISS, /SHUFFLE, /PERTURB) must be specified.");
      Put_Line ("  If more than one operation is listed, each record is assigned to at most");
      Put_Line ("  one operation; the probabilities must therefore sum to <= 1.0.");
      Put_Line ("  Records whose combined probability leaves a remainder receive no change.");
      Put_Line ("  /PERTURB is not valid for character variables.");
      New_Line;
      Put_Line ("Examples:");
      Put_Line ("  VANDALIZE SCORE INTO SCORE_NOISY /PERTURB=1.0,0.05");
      Put_Line ("    Copy SCORE to SCORE_NOISY, adding Gaussian noise with SD = 5% of");
      Put_Line ("    the column standard deviation.");
      New_Line;
      Put_Line ("  VANDALIZE INCOME INTO INCOME_BAD /MISS=0.10 /SHUFFLE=0.05");
      Put_Line ("    10% of records become missing; 5% get a random value from the column;");
      Put_Line ("    the remaining 85% are copied unchanged.");
      New_Line;
      Put_Line ("  VANDALIZE AGE INTO AGE /PERTURB /BY=DEPT$");
      Put_Line ("    Perturb AGE in-place using noise calibrated within each DEPT$ group.");
      New_Line;
      Put_Line ("Execution: Immediate -- operates on the current Data Table at once.");
   end Help_VANDALIZE;

   procedure Help_SORT is
   begin
      Put_Line ("Command: SORT variable(s)");
      Put_Line ("Reorders the Data Table based on the specified variables.");
      Put_Line ("Execution: Immediate -- re-orders the table at once.");
   end Help_SORT;

   procedure Help_NEW is
   begin
      Put_Line ("Command: NEW");
      Put_Line ("Clears the Data Table, all variables, and the queued program.");
      Put_Line ("Also resets the active SELECT record filter and BY grouping.");
      Put_Line ("Execution: Immediate -- takes effect at once.");
   end Help_NEW;

   procedure Help_LIST is
   begin
      Put_Line ("Command: LIST");
      Put_Line ("Execution: Immediate");
      Put_Line ("Displays the numbered contents of the program buffer (deferred statements");
      Put_Line ("queued for the next RUN).  If the buffer is empty, reports that fact.");
      Put_Line ("See also: DISPLAY to show Data Table records.");
      Put_Line ("          DELETE n[-m] to remove program buffer entries.");
   end Help_LIST;

   procedure Help_DISPLAY is
   begin
      Put_Line ("Command: DISPLAY [variable(s)]");
      Put_Line ("Execution: Immediate");
      Put_Line ("Displays the current Data Table as a formatted table.");
      Put_Line ("  DISPLAY         -- show all columns.");
      Put_Line ("  DISPLAY varlist -- show only the named columns.");
      Put_Line ("Respects any active SELECT filter (only visible records are shown).");
      Put_Line ("Column ranges are supported:  DISPLAY A-Z");
   end Help_DISPLAY;

   procedure Help_NAMES is
   begin
      Put_Line ("Command: NAMES");
      Put_Line ("Lists currently defined permanent and temporary variables.");
      Put_Line ("Execution: Immediate -- takes effect at once.");
   end Help_NAMES;

   procedure Help_DELETE is
   begin
      Put_Line ("Command: DELETE");
      Put_Line ("Two forms:");
      Put_Line ("  DELETE           Discard the current record; no output is produced for it.");
      Put_Line ("                   Execution: Deferred -- executed per record in the data step.");
      Put_Line ("  DELETE n[-m]     Remove program buffer entries n through m (1-based).");
      Put_Line ("                   A single number removes one entry; n-m removes a range.");
      Put_Line ("                   Execution: Immediate -- takes effect at once.");
      Put_Line ("                   Only meaningful in interactive (REPL) mode.");
   end Help_DELETE;

   procedure Help_BREAK is
   begin
      Put_Line ("Command: BREAK  |  BREAK WHEN <boolean-expr>");
      Put_Line ("Pauses execution and enters the debug inspection prompt.");
      Put_Line ("Valid only inside a data step (deferred context); ignored in immediate mode.");
      Put_Line ("BREAK always pauses. BREAK WHEN <expr> pauses only when the condition is true.");
      Put_Line ("Examples:");
      Put_Line ("  BREAK                   -- pause on every record");
      Put_Line ("  BREAK WHEN RECNO() = 5  -- pause on record 5 only");
      Put_Line ("  BREAK WHEN SALARY > 100000");
      New_Line;
      Put_Line ("When paused, the inspection prompt accepts:");
      Put_Line ("  PRINT <expr>   Evaluate and display any SData expression");
      Put_Line ("  RECORD N       Load record N into the inspection view");
      Put_Line ("  RECORD +N      Advance N records from current inspection position");
      Put_Line ("  RECORD -N      Go back N records from current inspection position");
      Put_Line ("  CONTINUE / C   Resume execution from the paused point");
      Put_Line ("  STEP / S       Resume to the next record, then pause again");
      Put_Line ("  RUN            Resume to completion with no further automatic pausing");
      New_Line;
      Put_Line ("In non-interactive mode (stdin not a TTY), BREAK emits a trace line to");
      Put_Line ("stderr and continues automatically without waiting for input.");
      Put_Line ("Execution: Deferred -- executed once per record inside the data step.");
   end Help_BREAK;

   procedure Help_DEBUGGER is
   begin
      Put_Line ("Debug mode: --debug[=N] flag  (N = 1, 2, or 3; default 3)");
      Put_Line ("Enables trace output to stderr and interactive step mode.");
      New_Line;
      Put_Line ("Verbosity levels:");
      Put_Line ("  1  sparse   I/O transitions only");
      Put_Line ("  2  normal   Level 1 + per-record header + control-flow outcomes");
      Put_Line ("  3  verbose  Level 2 + every LET/SET assignment");
      New_Line;
      Put_Line ("Level 1 trace events:");
      Put_Line ("  [debug] USE: opened file.csv (N records, M variables)");
      Put_Line ("  [debug] SUBMIT: entering script.sdata");
      Put_Line ("  [debug] RUN complete: N records, M variables");
      New_Line;
      Put_Line ("Level 2 adds:");
      Put_Line ("  [debug] -- record N (physical P)  [BY GROUP ...]");
      Put_Line ("  [debug] IF -> TRUE / FALSE");
      Put_Line ("  [debug] ELSE -> taken");
      Put_Line ("  [debug] FOR I = 3");
      Put_Line ("  [debug] SELECT -> KEPT / DROPPED");
      Put_Line ("  [debug] SELECT -> N of M records kept");
      Put_Line ("  [debug] DELETE: record marked");
      New_Line;
      Put_Line ("Level 3 adds:");
      Put_Line ("  [debug] LET X = 5.00000         each scalar or array assignment");
      Put_Line ("  [debug] SET X = 5.00000");
      New_Line;
      Put_Line ("Runtime control:  OPTIONS DEBUG N  (0 disables tracing)");
      New_Line;
      Put_Line ("Step mode (--debug[=N] + interactive stdin):");
      Put_Line ("  After each record header, execution pauses at the inspection prompt.");
      Put_Line ("  CONTINUE/C processes the current record and advances to the next.");
      Put_Line ("  STEP/S is equivalent to CONTINUE in step mode.");
      Put_Line ("  RUN at the prompt disables step mode and runs to completion.");
      New_Line;
      Put_Line ("The inspection prompt ([debug:record N]>) accepts the same commands as");
      Put_Line ("BREAK: PRINT, RECORD, CONTINUE, STEP, RUN.  Record navigation at the");
      Put_Line ("prompt does not affect which record is processed when execution resumes.");
      New_Line;
      Put_Line ("See also: HELP BREAK for the BREAK / BREAK WHEN deferred statement.");
   end Help_DEBUGGER;

   procedure Help_HOLD is
   begin
      Put_Line ("Command: HOLD [variable(s)]");
      Put_Line ("Retains the listed permanent variables across records.");
      Put_Line ("Execution: Deferred -- executed once per record inside the data step.");
   end Help_HOLD;

   procedure Help_UNHOLD is
   begin
      Put_Line ("Command: UNHOLD [variable(s)]");
      Put_Line ("Cancels a previous HOLD. No args = unhold all.");
      Put_Line ("Execution: Deferred -- executed once per record inside the data step.");
   end Help_UNHOLD;

   procedure Help_KEEP is
   begin
      Put_Line ("Command: KEEP variable(s)");
      Put_Line ("Drops all permanent variables NOT listed after the next RUN.");
      Put_Line ("Execution: Declarative -- columns are removed at the end of the next RUN.");
   end Help_KEEP;

   procedure Help_DROP is
   begin
      Put_Line ("Command: DROP variable(s)");
      Put_Line ("Drops the listed permanent variables after the next RUN.");
      Put_Line ("Execution: Declarative -- columns are removed at the end of the next RUN.");
   end Help_DROP;

   procedure Help_RENAME is
   begin
      Put_Line ("Command: RENAME old=new [, old=new ...]");
      Put_Line ("Renames columns in the Data Table.");
      Put_Line ("Execution: Immediate -- takes effect at once.");
   end Help_RENAME;

   procedure Help_IF is
   begin
      Put_Line ("Command: IF condition THEN stmt [ELSEIF cond THEN stmt] [ELSE stmt]");
      Put_Line ("Conditional execution. Supports single-line and multi-line block forms.");
      Put_Line ("Example:");
      Put_Line ("  IF AGE < 18 THEN");
      Put_Line ("    LET STATUS$ = ""MINOR""");
      Put_Line ("  ELSEIF AGE < 65 THEN");
      Put_Line ("    LET STATUS$ = ""ADULT""");
      Put_Line ("  ELSE");
      Put_Line ("    LET STATUS$ = ""SENIOR""");
      Put_Line ("  END IF");
      New_Line;
      Put_Line ("Also usable as a function: IF(condition, true_value, false_value)");
      Put_Line ("Returns true_value when condition is non-zero/non-empty, else false_value.");
      Put_Line ("Example: LET STATUS$ = IF(AGE < 18, ""MINOR"", ""ADULT"")");
      Put_Line ("Execution: Deferred -- executed once per record inside the data step.");
   end Help_IF;

   procedure Help_SELECT is
   begin
      Put_Line ("-- Record filter form ----------------------------------------");
      Put_Line ("Command: SELECT expression  |  SELECT /ALL");
      Put_Line ("Activates a virtual record filter for subsequent RUNs.");
      Put_Line ("Only records for which <expression> is true are visible;");
      Put_Line ("RECNO, BOF, EOF, BOG, EOG, LAG, and NEXT all operate within");
      Put_Line ("the filtered (logical) view.  The filter is rebuilt automatically");
      Put_Line ("at the start of every RUN against the current table.");
      Put_Line ("SELECT /ALL cancels the active filter and restores all records.");
      Put_Line ("The filter persists until SELECT /ALL or NEW is executed.");
      Put_Line ("Example:");
      Put_Line ("  select score > 70   -- keep only high scorers");
      Put_Line ("  run");
      Put_Line ("  select /all         -- cancel filter");
      Put_Line ("Execution: Declarative -- filter is active for all subsequent RUNs.");
      New_Line;
      Put_Line ("-- Multi-way branch form --------------------------------------");
      Put_Line ("Command: SELECT [expression]");
      Put_Line ("  CASE value : statement");
      Put_Line ("  WHEN condition : statement");
      Put_Line ("  OTHERWISE : statement");
      Put_Line ("END SELECT");
      Put_Line ("Example:");
      Put_Line ("  SELECT GRADE$");
      Put_Line ("    CASE ""A"" : PRINT ""EXCELLENT""");
      Put_Line ("    CASE ""B"" : PRINT ""GOOD""");
      Put_Line ("    OTHERWISE : PRINT ""SEE ME""");
      Put_Line ("  END SELECT");
      Put_Line ("Execution: Deferred -- executed once per record inside the data step.");
   end Help_SELECT;

   procedure Help_FOR is
   begin
      Put_Line ("Command: FOR var = start TO end [STEP s] ... NEXT");
      Put_Line ("Counter-controlled loop.");
      Put_Line ("Example:");
      Put_Line ("  FOR I = 1 TO 10 STEP 2");
      Put_Line ("    PRINT I");
      Put_Line ("  NEXT I");
      Put_Line ("Execution: Deferred -- executed once per record inside the data step.");
   end Help_FOR;

   procedure Help_WHILE is
   begin
      Put_Line ("Command: WHILE condition ... WEND");
      Put_Line ("Condition-controlled loop; executes while condition is true.");
      Put_Line ("Example:");
      Put_Line ("  SET I = 1");
      Put_Line ("  WHILE I <= 10");
      Put_Line ("    PRINT I");
      Put_Line ("    SET I = I + 1");
      Put_Line ("  WEND");
      Put_Line ("Execution: Deferred -- executed once per record inside the data step.");
   end Help_WHILE;

   procedure Help_REPEAT is
   begin
      Put_Line ("Command (data step): REPEAT n  (creates n records)");
      Put_Line ("Execution: Declarative -- the n-record mode is active for the next RUN.");
      New_Line;
      Put_Line ("Command (loop): REPEAT ... UNTIL condition");
      Put_Line ("Post-test loop; always executes the body at least once.");
      Put_Line ("Example:");
      Put_Line ("  SET I = 1");
      Put_Line ("  REPEAT");
      Put_Line ("    PRINT I");
      Put_Line ("    SET I = I + 1");
      Put_Line ("  UNTIL I > 10");
      Put_Line ("Execution: Deferred -- executed once per record inside the data step.");
   end Help_REPEAT;

   procedure Help_OUTPUT is
   begin
      Put_Line ("Command: OUTPUT [""filename""] [/CHARSET=...] [/FMT=...]");
      Put_Line ("Redirects all console output to a file (written to file AND stdout).");
      Put_Line ("No arguments: Closes the current output file.");
      Put_Line ("Options:");
      Put_Line ("  /CHARSET=cs  Specifies the character set (e.g., UTF-8, ASCII).");
      Put_Line ("  /FMT=format  Specifies the file format (e.g., CSV, ODF).");
      Put_Line ("Execution: Immediate -- takes effect at once.");
   end Help_OUTPUT;

   procedure Help_ECHO is
   begin
      Put_Line ("Command: ECHO ON | OFF");
      Put_Line ("Enables or disables writing console output to stdout.");
      Put_Line ("Execution: Immediate -- takes effect at once.");
   end Help_ECHO;

   procedure Help_DIGITS is
   begin
      Put_Line ("Command: DIGITS n");
      Put_Line ("Sets decimal places for floating-point output (default 5).");
      Put_Line ("Execution: Immediate -- takes effect at once.");
   end Help_DIGITS;

   procedure Help_FPATH is
   begin
      Put_Line ("Command: FPATH [path] [/ USE | SAVE | SUBMIT | OUTPUT]");
      Put_Line ("Sets the default directory for the specified command(s).");
      Put_Line ("Execution: Declarative -- applies to all subsequent file commands.");
   end Help_FPATH;

   procedure Help_RSEED is
   begin
      Put_Line ("Command: RSEED n");
      Put_Line ("Seeds the random number generator with integer n.");
      Put_Line ("Execution: Immediate -- takes effect at once.");
   end Help_RSEED;

   procedure Help_HELP is
   begin
      Put_Line ("Command: HELP [topic | /ALL]");
      Put_Line ("Displays help. HELP /ALL prints the full reference.");
      Put_Line ("Execution: Immediate -- takes effect at once.");
   end Help_HELP;

   procedure Help_QUIT is
   begin
      Put_Line ("Command: QUIT | END");
      Put_Line ("Exits the interpreter.");
      Put_Line ("Execution: Immediate -- exits at once.");
   end Help_QUIT;

   procedure Help_OPTIONS is
   begin
      Put_Line ("Command: OPTIONS [key value]");
      Put_Line ("Sets a runtime option. Execution: Immediate -- takes effect at once.");
      Put_Line ("With no arguments, OPTIONS lists all current option values.");
      Put_Line ("");
      Put_Line ("  OPTIONS MAXINTAB n         : Max in-memory table cells (rows*cols; 0 = unlimited)");
      Put_Line ("  OPTIONS MAXTEMPMEM n       : Max temporary variables (0 = unlimited)");
      Put_Line ("  OPTIONS CSVDLM "",""|""\t""|"";""|""|""  : CSV field delimiter (default: comma)");
      Put_Line ("  OPTIONS HEADER YES|NO      : CSV files have a header row (default: YES)");
      Put_Line ("  OPTIONS SAVEOVERWRT YES|NO : Overwrite existing files on SAVE (default: YES)");
      Put_Line ("  OPTIONS TXTFMT AUTO|LF|CRLF|CR  : Line ending for CSV output (default: AUTO)");
      Put_Line ("  OPTIONS CHARSET name       : Character set label (stored, advisory only)");
      Put_Line ("  OPTIONS IEEE_DIVIDE YES|NO : Float /0 -> +/-Inf instead of error (default: NO)");
      Put_Line ("                               0.0/0.0 always raises an error. Cleared by NEW.");
      Put_Line ("  OPTIONS SHELLTIMEOUT n     : SYSTEM/SHELL timeout in seconds (0 = unlimited). Cleared by NEW.");
      Put_Line ("");
      Put_Line ("CLI flags (set at startup, not runtime):");
      Put_Line ("  --shell-timeout=N    : SYSTEM/SHELL timeout in seconds (0 = unlimited; default 300 in batch)");
      Put_Line ("  --noshell            : Disable SYSTEM/SHELL; also disables -p");
      Put_Line ("  --nosubmit           : Disable SUBMIT");
      Put_Line ("  --ignore-math-errors : Domain errors return MISSING");
      Put_Line ("  --clen <n>           : Set max character variable length");
      Put_Line ("  -m <n>               : Set max in-memory table cells (rows*cols; 0 = unlimited)");
      Put_Line ("  -t <n>               : Set max temporary variables");
      Put_Line ("  -k                   : Continue execution after statement error");
      Put_Line ("  -p <pager>           : External pager for interactive output");
      Put_Line ("  -q                   : Quiet mode (suppress console output)");
      Put_Line ("  -o <file>            : Redirect console output to file");
      Put_Line ("  -u <fmt>             : Default input format (CSV/ODF/OOXML)");
      Put_Line ("  -s <fmt>             : Default output format (CSV/ODF/OOXML)");
   end Help_OPTIONS;

   procedure Help_EXECUTION is
   begin
      Put_Line ("Execution Tiers");
      Put_Line ("sdata commands fall into three execution tiers:");
      New_Line;
      Put_Line ("  Declarative -- configure state for the next RUN.");
      Put_Line ("    These commands take effect immediately but their primary");
      Put_Line ("    action occurs when RUN is executed.");
      Put_Line ("    Commands: USE, SAVE, BY, SELECT (filter), SELECT /ALL,");
      Put_Line ("              REPEAT n, KEEP, DROP, FPATH");
      New_Line;
      Put_Line ("  Immediate -- execute at once, outside any data step.");
      Put_Line ("    Commands: RUN, SORT, NEW, NAMES, LIST, DISPLAY, UNSET, RENAME,");
      Put_Line ("              SYSTEM, SUBMIT, ECHO, DIGITS, RSEED, OUTPUT, HELP,");
      Put_Line ("              DELETE n[-m], QUIT, END");
      New_Line;
      Put_Line ("  Deferred -- queued between RUN markers; executed once per");
      Put_Line ("    record during the data step.");
      Put_Line ("    Commands: LET, SET, PRINT, IF, FOR, WHILE, REPEAT/UNTIL,");
      Put_Line ("              SELECT/CASE, DELETE, WRITE, HOLD, UNHOLD,");
      Put_Line ("              ARRAY, DIM, BREAK");
      New_Line;
      Put_Line ("Note: SELECT has two forms with different tiers:");
      Put_Line ("  SELECT <expr> / SELECT /ALL  -- Declarative (row filter)");
      Put_Line ("  SELECT CASE ... END SELECT   -- Deferred (multi-way branch)");
      New_Line;
      Put_Line ("The HELP entry for each command includes an ""Execution:"" line");
      Put_Line ("identifying which tier it belongs to.");
   end Help_EXECUTION;

   procedure Help_CONCEPTS is
   begin
      Put_Line ("Concepts: PDV, LET vs SET, and BY Groups");
      New_Line;
      Put_Line ("--- Program Data Vector (PDV) ---");
      Put_Line ("A data step processes the table one record at a time.  For each record");
      Put_Line ("sdata loads the source row into the PDV (Program Data Vector), executes");
      Put_Line ("all deferred statements (LET, SET, IF, PRINT, ...), then writes the");
      Put_Line ("result to the output table.");
      New_Line;
      Put_Line ("Each permanent variable (LET column) is reset to MISSING at the start of");
      Put_Line ("every record before the source row is loaded.  HOLD retains a value");
      Put_Line ("across records:");
      Put_Line ("  HOLD RUNNING_TOT   -- carry RUNNING_TOT forward from the previous record");
      New_Line;
      Put_Line ("--- LET vs SET ---");
      Put_Line ("Both assign values inside the data step, but their persistence differs:");
      New_Line;
      Put_Line ("  LET var = expr   Permanent column.  Written to the output table;");
      Put_Line ("                   visible after RUN in DISPLAY, NAMES, and SAVE.");
      Put_Line ("                   Reset to MISSING at the start of each record");
      Put_Line ("                   unless retained by HOLD.");
      New_Line;
      Put_Line ("  SET var = expr   Session variable.  NOT written to the output table.");
      Put_Line ("                   NOT reset between records or between RUN calls.");
      Put_Line ("                   Persists until UNSET, NEW, or the session ends.");
      Put_Line ("                   Use SET for counters and values that should not");
      Put_Line ("                   appear as output columns.");
      New_Line;
      Put_Line ("A common mistake: using LET for a counter that should not appear as an");
      Put_Line ("output column.  Use SET instead.");
      New_Line;
      Put_Line ("--- BY Groups ---");
      Put_Line ("BY variable(s) partitions records into groups whose members share the same");
      Put_Line ("values for the listed variables.  Records must already be in group order;");
      Put_Line ("use SORT first if needed.  Bare BY (no variables) cancels grouping.");
      New_Line;
      Put_Line ("  BOG()   1 at the first record of each group, 0 otherwise");
      Put_Line ("  EOG()   1 at the last record of each group, 0 otherwise");
      New_Line;
      Put_Line ("LAG and NEXT respect group boundaries: they return MISSING rather than");
      Put_Line ("reading into an adjacent group.");
      New_Line;
      Put_Line ("Example -- subtotal SALARY by DEPT:");
      Put_Line ("  SORT DEPT$");
      Put_Line ("  BY DEPT$");
      Put_Line ("  HOLD DEPT_TOT");
      Put_Line ("  IF BOG() THEN SET DEPT_TOT = 0");
      Put_Line ("  SET DEPT_TOT = DEPT_TOT + SALARY");
      Put_Line ("  IF EOG() THEN PRINT DEPT$, DEPT_TOT");
      Put_Line ("  RUN");
      New_Line;
      Put_Line ("See also: HELP LET  HELP SET  HELP BY  HELP HOLD  HELP EXECUTION");
   end Help_CONCEPTS;

   -- ==========================================================================
   --  Math functions
   -- ==========================================================================

   procedure Help_ABS   is begin Put_Line ("Function: ABS(x)  ->  |x|"); end Help_ABS;
   procedure Help_SQRT  is begin Put_Line ("Function: SQRT(x) / SQR(x)  ->  square root of x (x >= 0)"); end Help_SQRT;
   procedure Help_SGN   is begin Put_Line ("Function: SGN(x)  ->  sign of x: -1, 0, or 1"); end Help_SGN;
   procedure Help_LOG   is begin Put_Line ("Function: LOG(x)  ->  natural logarithm (x > 0)"); end Help_LOG;
   procedure Help_LOG10 is begin Put_Line ("Function: LOG10(x)  ->  base-10 logarithm (x > 0)"); end Help_LOG10;
   procedure Help_EXP   is begin Put_Line ("Function: EXP(x)  ->  e raised to the power x"); end Help_EXP;
   procedure Help_ROUND is begin Put_Line ("Function: ROUND(x [, n])  ->  x rounded to n decimal places (default 0)"); end Help_ROUND;
   procedure Help_CEIL  is begin Put_Line ("Function: CEIL(x)  ->  smallest integer >= x"); end Help_CEIL;
   procedure Help_FLOOR is begin Put_Line ("Function: FLOOR(x)  ->  largest integer <= x"); end Help_FLOOR;
   procedure Help_INT   is begin Put_Line ("Function: INT(x)  ->  largest integer <= x (floor; rounds toward -infinity)"); end Help_INT;
   procedure Help_FIX   is begin Put_Line ("Function: FIX(x) / IP(x)  ->  integer part, truncated toward zero"); end Help_FIX;
   procedure Help_FP    is begin Put_Line ("Function: FP(x)  ->  fractional part: x - FIX(x)"); end Help_FP;
   procedure Help_LOG2  is begin Put_Line ("Function: LOG2(x)  ->  base-2 logarithm (x > 0)"); end Help_LOG2;
   procedure Help_LN    is begin Put_Line ("Function: LN(x) / LOGE(x)  ->  natural logarithm (aliases for LOG; x > 0)"); end Help_LN;
   procedure Help_CLG   is begin Put_Line ("Function: CLG(x) / LGT(x)  ->  common (base-10) logarithm (aliases for LOG10; x > 0)"); end Help_CLG;
   procedure Help_MOD   is begin Put_Line ("Function: MOD(x, y)  ->  x mod y (floor division remainder)"); end Help_MOD;

   -- ==========================================================================
   --  Trig functions (radians)
   -- ==========================================================================

   procedure Help_SIN   is begin Put_Line ("Function: SIN(x)  ->  sine of x (radians)"); end Help_SIN;
   procedure Help_COS   is begin Put_Line ("Function: COS(x)  ->  cosine of x (radians)"); end Help_COS;
   procedure Help_TAN   is begin Put_Line ("Function: TAN(x)  ->  tangent of x (radians)"); end Help_TAN;
   procedure Help_ATN   is begin Put_Line ("Function: ATN(x)  ->  arctangent of x (radians)"); end Help_ATN;
   procedure Help_ATAN2 is begin Put_Line ("Function: ATAN2(y, x)  ->  arctangent of y/x (radians)"); end Help_ATAN2;
   procedure Help_SINH   is begin Put_Line ("Function: SINH(x) / HSN(x)  ->  hyperbolic sine"); end Help_SINH;
   procedure Help_COSH   is begin Put_Line ("Function: COSH(x) / HCS(x)  ->  hyperbolic cosine"); end Help_COSH;
   procedure Help_TANH   is begin Put_Line ("Function: TANH(x) / HTN(x)  ->  hyperbolic tangent"); end Help_TANH;
   procedure Help_ARCSIN is begin Put_Line ("Function: ARCSIN(x)  ->  arcsine of x in radians (-1 <= x <= 1)"); end Help_ARCSIN;
   procedure Help_ARCCOS is begin Put_Line ("Function: ARCCOS(x)  ->  arccosine of x in radians (-1 <= x <= 1)"); end Help_ARCCOS;
   procedure Help_ARCTAN is begin Put_Line ("Function: ARCTAN(x) / ATN(x)  ->  arctangent of x in radians"); end Help_ARCTAN;
   procedure Help_COT    is begin Put_Line ("Function: COT(x)  ->  cotangent of x (radians); cos(x)/sin(x)"); end Help_COT;
   procedure Help_CSC    is begin Put_Line ("Function: CSC(x)  ->  cosecant of x (radians); 1/sin(x)"); end Help_CSC;
   procedure Help_SEC    is begin Put_Line ("Function: SEC(x)  ->  secant of x (radians); 1/cos(x)"); end Help_SEC;
   procedure Help_DEG    is begin Put_Line ("Function: DEG(x) / DEGREE(x)  ->  convert x from radians to degrees"); end Help_DEG;

   -- ==========================================================================
   --  Trig functions (degrees)
   -- ==========================================================================

   procedure Help_SIND   is begin Put_Line ("Function: SIND(x)    ->  sine of x (degrees)"); end Help_SIND;
   procedure Help_COSD   is begin Put_Line ("Function: COSD(x)    ->  cosine of x (degrees)"); end Help_COSD;
   procedure Help_TAND   is begin Put_Line ("Function: TAND(x)    ->  tangent of x (degrees)"); end Help_TAND;
   procedure Help_ATND   is begin Put_Line ("Function: ATND(x)    ->  arctangent of x (degrees)"); end Help_ATND;
   procedure Help_ATAN2D is begin Put_Line ("Function: ATAN2D(y,x) ->  arctangent of y/x (degrees)"); end Help_ATAN2D;

   -- ==========================================================================
   --  String functions
   -- ==========================================================================

   procedure Help_LEN    is begin Put_Line ("Function: LEN(s$)  ->  length of string s$"); end Help_LEN;
   procedure Help_LEFTS  is begin Put_Line ("Function: LEFT$(s$, n)  ->  leftmost n characters"); end Help_LEFTS;
   procedure Help_RIGHTS is begin Put_Line ("Function: RIGHT$(s$, n)  ->  rightmost n characters"); end Help_RIGHTS;
   procedure Help_MIDS   is begin Put_Line ("Function: MID$(s$, start [, len])  ->  substring"); end Help_MIDS;
   procedure Help_SEGS   is begin Put_Line ("Function: SEG$(s$, start, len)  ->  substring (start 0=1; len > 0 required)"); end Help_SEGS;
   procedure Help_FRAC   is begin Put_Line ("Function: FRAC(x)  ->  fractional part of x (alias for FP)"); end Help_FRAC;
   procedure Help_TRIMS  is begin Put_Line ("Function: TRIM$(s$)  ->  strip leading and trailing spaces"); end Help_TRIMS;
   procedure Help_LTRIMS is begin Put_Line ("Function: LTRIM$(s$)  ->  strip leading spaces"); end Help_LTRIMS;
   procedure Help_RTRIMS is begin Put_Line ("Function: RTRIM$(s$)  ->  strip trailing spaces"); end Help_RTRIMS;
   procedure Help_UCASES is begin Put_Line ("Function: UCASE$(s$) / UPPER$(s$)  ->  convert to upper case"); end Help_UCASES;
   procedure Help_LCASES is begin Put_Line ("Function: LCASE$(s$) / LOWER$(s$)  ->  convert to lower case"); end Help_LCASES;
   procedure Help_POS    is begin Put_Line ("Function: POS(needle$, haystack$)  ->  1-based position, 0=not found"); end Help_POS;
   procedure Help_INSTR  is begin Put_Line ("Function: INSTR(haystack$, needle$)  ->  1-based position, 0=not found (BW BASIC argument order)"); end Help_INSTR;
   procedure Help_CHRS   is begin Put_Line ("Function: CHR$(n)  ->  character with ASCII code n"); end Help_CHRS;
   procedure Help_ASCII  is begin Put_Line ("Function: ASCII(s$) / ASC(s$)  ->  ASCII code of first character of s$"); end Help_ASCII;
   procedure Help_STRS   is begin Put_Line ("Function: STR$(x)  ->  numeric x formatted as string"); end Help_STRS;
   procedure Help_VAL    is begin Put_Line ("Function: VAL(s$)  ->  parse string s$ as a number"); end Help_VAL;
   procedure Help_NUMS   is begin Put_Line ("Function: NUM$(x)  ->  numeric x formatted as string (alias for STR$)"); end Help_NUMS;
   procedure Help_NUM    is begin Put_Line ("Function: NUM(x)  ->  convert string or integer x to float"); end Help_NUM;

   -- ==========================================================================
   --  Base conversion
   -- ==========================================================================

   procedure Help_HEXS is begin Put_Line ("Function: HEX$(n)  ->  hexadecimal string for integer n"); end Help_HEXS;
   procedure Help_HEX  is begin Put_Line ("Function: HEX(s$)  ->  integer value of hexadecimal string s$"); end Help_HEX;
   procedure Help_OCTS is begin Put_Line ("Function: OCT$(n)  ->  octal string for integer n"); end Help_OCTS;
   procedure Help_BINS is begin Put_Line ("Function: BIN$(n)  ->  binary string for integer n"); end Help_BINS;

   -- ==========================================================================
   --  Record navigation
   -- ==========================================================================

   procedure Help_RECNO is
   begin
      Put_Line ("Function: RECNO()  ->  current logical record number (1-based)");
      Put_Line ("  When a SELECT filter is active, RECNO counts only visible records.");
   end Help_RECNO;

   procedure Help_BOF is
   begin
      Put_Line ("Function: BOF()  ->  1 if this is the first visible record, else 0");
      Put_Line ("  Respects any active SELECT filter (logical first record).");
   end Help_BOF;

   procedure Help_EOF is
   begin
      Put_Line ("Function: EOF()  ->  1 if this is the last visible record, else 0");
      Put_Line ("  Respects any active SELECT filter (logical last record).");
   end Help_EOF;

   procedure Help_BOG is
   begin
      Put_Line ("Function: BOG()  ->  1 at the start of a BY group, else 0");
      Put_Line ("  Operates in logical space; filtered-out records are invisible.");
   end Help_BOG;

   procedure Help_EOG is
   begin
      Put_Line ("Function: EOG()  ->  1 at the end of a BY group, else 0");
      Put_Line ("  Operates in logical space; filtered-out records are invisible.");
   end Help_EOG;

   procedure Help_LAG is
   begin
      Put_Line ("Function: LAG(""varname"" [, n]) / LAGC$(""varname"" [, n])");
      Put_Line ("Returns the value of the named variable n records back (default n=1).");
      Put_Line ("Returns missing at the start of the dataset or at a BY-group boundary.");
      Put_Line ("When a SELECT filter is active, only visible (logical) records are counted;");
      Put_Line ("filtered-out rows are completely invisible to LAG.");
      Put_Line ("The variable name may be given unquoted: LAG(X) is equivalent to LAG(""X"").");
      Put_Line ("LAG returns a numeric value; LAGC$ returns a string value.");
   end Help_LAG;

   procedure Help_NEXT is
   begin
      Put_Line ("Function: NEXT(""varname"" [, n]) / NEXTC$(""varname"" [, n])");
      Put_Line ("Returns the value of the named variable n records ahead (default n=1).");
      Put_Line ("Returns missing at the end of the dataset or at a BY-group boundary.");
      Put_Line ("When a SELECT filter is active, only visible (logical) records are counted;");
      Put_Line ("filtered-out rows are completely invisible to NEXT.");
      Put_Line ("The variable name may be given unquoted: NEXT(X) is equivalent to NEXT(""X"").");
      Put_Line ("NEXT returns a numeric value; NEXTC$ returns a string value.");
   end Help_NEXT;

   procedure Help_OBS is
   begin
      Put_Line ("Function: OBS(""varname"", row) / OBSC$(""varname"", row)");
      Put_Line ("Returns the value of the named variable from the specified physical row.");
      Put_Line ("row: 1-based row index in the Data Table, counting all rows regardless of");
      Put_Line ("any active SELECT filter (i.e. OBS ignores the logical/filtered view).");
      Put_Line ("Returns missing if row < 1 or row > total row count.");
      Put_Line ("The variable name may be given unquoted: OBS(X, 3) is equivalent to OBS(""X"", 3).");
      Put_Line ("OBS returns a numeric value; OBSC$ returns a string value.");
   end Help_OBS;

   -- ==========================================================================
   --  Special functions
   -- ==========================================================================

   procedure Help_MISSING is begin Put_Line ("Function: MISSING(x)  ->  1 if x is missing, else 0"); end Help_MISSING;

   procedure Help_INF is
   begin
      Put_Line ("Function: INF(x)  ->  1 if x is +Inf or -Inf, else 0");
      Put_Line ("  Returns 0 for finite numeric values, missing values, and strings.");
      Put_Line ("");
      Put_Line ("  To test for positive infinity:  INF(x) AND x > 0");
      Put_Line ("  To test for negative infinity:  INF(x) AND x < 0");
      Put_Line ("  NOT INF(x) serves the role of FINITE() for non-missing values.");
      Put_Line ("");
      Put_Line ("  Inf arises from arithmetic overflow (MAXNUM() * 2.0) or from");
      Put_Line ("  float division by zero when OPTIONS IEEE_DIVIDE YES is set.");
      Put_Line ("  See also: MISSING, OPTIONS IEEE_DIVIDE");
   end Help_INF;

   procedure Help_RAN is
   begin
      Put_Line ("Function: RAN() / RANDOM() / RND()  ->  uniform random number in [0, 1)");
      Put_Line ("  Use RSEED n before calling to get a reproducible sequence.");
   end Help_RAN;

   procedure Help_DATES is begin Put_Line ("Function: DATE$()  ->  current date as ""YYYY-MM-DD"""); end Help_DATES;
   procedure Help_TIMES is begin Put_Line ("Function: TIME$()  ->  current time as ""HH:MM:SS"""); end Help_TIMES;

   procedure Help_SHELL is
   begin
      Put_Line ("Function: SHELL(""command"")  ->  0 on success, 1 on failure");
      Put_Line ("  Disabled by --noshell flag.");
   end Help_SHELL;

   procedure Help_FALSE is begin Put_Line ("Function: FALSE  ->  0 (numeric false constant)"); end Help_FALSE;
   procedure Help_TRUE  is begin Put_Line ("Function: TRUE   ->  1 (numeric true constant)"); end Help_TRUE;

   procedure Help_ERR is
   begin
      Put_Line ("Function: ERR()  ->  last error code (0 = no error, 1 = error caught)");
      Put_Line ("  Set when an error is caught by -k (--continue-on-error).");
      Put_Line ("  Not set by --ignore-math-errors domain warnings.");
      Put_Line ("  Reset to 0 by the NEW command.");
   end Help_ERR;

   procedure Help_ERL is
   begin
      Put_Line ("Function: ERL()  ->  record number where the last caught error occurred");
      Put_Line ("  Returns 0 if no error has been caught in the current session.");
      Put_Line ("  Set alongside ERR() when -k catches a runtime error.");
      Put_Line ("  Reset to 0 by the NEW command.");
   end Help_ERL;

   -- ==========================================================================
   --  Aggregate functions
   -- ==========================================================================

   procedure Help_SUM is
   begin
      Put_Line ("Function: SUM(v1 [, v2, ...])");
      Put_Line ("Returns the sum of non-missing values across the arguments.");
      Put_Line ("Missing values are skipped; SUM of all-missing arguments returns 0.");
      Put_Line ("Arguments may be individual values or array names (expanded automatically).");
   end Help_SUM;

   procedure Help_MEAN is
   begin
      Put_Line ("Function: MEAN(v1 [, v2, ...])");
      Put_Line ("Returns the arithmetic mean of non-missing values across the arguments.");
      Put_Line ("Missing values are excluded; the divisor is the non-missing count.");
      Put_Line ("Arguments may be individual values or array names (expanded automatically).");
   end Help_MEAN;

   procedure Help_STD is
   begin
      Put_Line ("Function: STD(v1 [, v2, ...])");
      Put_Line ("Returns the sample standard deviation (n-1 denominator) of non-missing values.");
      Put_Line ("Returns missing when fewer than 2 non-missing values are supplied.");
      Put_Line ("Arguments may be individual values or array names (expanded automatically).");
   end Help_STD;

   procedure Help_VAR is
   begin
      Put_Line ("Function: VAR(v1 [, v2, ...])");
      Put_Line ("Returns the sample variance (n-1 denominator) of non-missing values.");
      Put_Line ("Returns missing when fewer than 2 non-missing values are supplied.");
      Put_Line ("Arguments may be individual values or array names (expanded automatically).");
   end Help_VAR;

   procedure Help_MIN is
   begin
      Put_Line ("Function: MIN(v1 [, v2, ...])");
      Put_Line ("Returns the smallest non-missing value across the arguments.");
      Put_Line ("Returns missing if all arguments are missing.");
   end Help_MIN;

   procedure Help_MAX is
   begin
      Put_Line ("Function: MAX(v1 [, v2, ...])");
      Put_Line ("Returns the largest non-missing value across the arguments.");
      Put_Line ("Returns missing if all arguments are missing.");
   end Help_MAX;

   procedure Help_MEDIAN is
   begin
      Put_Line ("Function: MEDIAN(v1 [, v2, ...])");
      Put_Line ("Returns the median of non-missing values across the arguments.");
      Put_Line ("Values are sorted internally; missing values are excluded.");
      Put_Line ("Returns missing if all arguments are missing.");
      Put_Line ("Arguments may be individual values or array names (expanded automatically).");
   end Help_MEDIAN;

   procedure Help_GMEAN is
   begin
      Put_Line ("Function: GMEAN(v1 [, v2, ...])");
      Put_Line ("Returns the geometric mean of non-missing values across the arguments.");
      Put_Line ("Returns missing if any argument is <= 0 or all arguments are missing.");
      Put_Line ("Arguments may be individual values or array names (expanded automatically).");
   end Help_GMEAN;

   procedure Help_HMEAN is
   begin
      Put_Line ("Function: HMEAN(v1 [, v2, ...])");
      Put_Line ("Returns the harmonic mean of non-missing values across the arguments.");
      Put_Line ("Returns missing if any argument is zero or all arguments are missing.");
      Put_Line ("Arguments may be individual values or array names (expanded automatically).");
   end Help_HMEAN;

   procedure Help_N is
   begin
      Put_Line ("Function: N(v1 [, v2, ...])");
      Put_Line ("Returns the count of non-missing values across the supplied arguments.");
      Put_Line ("Arguments may be individual values or array names (expanded automatically).");
   end Help_N;

   procedure Help_NMISS is
   begin
      Put_Line ("Function: NMISS(v1 [, v2, ...])");
      Put_Line ("Returns the count of missing values across the supplied arguments.");
      Put_Line ("Arguments may be individual values or array names (expanded automatically).");
   end Help_NMISS;

   -- ==========================================================================
   --  Statistical distributions
   -- ==========================================================================

   procedure Help_DISTRIBUTIONS is
   begin
      Put_Line ("Statistical distribution functions follow a uniform naming convention.");
      New_Line;
      Put_Line ("Function suffix meanings:");
      Put_Line ("  DF   Probability density function (PDF) or probability mass (PMF)");
      Put_Line ("  CF   Cumulative distribution function: P(X <= x)");
      Put_Line ("  IF   Inverse CDF (quantile): value x such that P(X <= x) = p  (0 < p < 1)");
      Put_Line ("  RN   Generate a random variate from the distribution");
      New_Line;
      Put_Line ("Common argument names:");
      Put_Line ("  x      Continuous variate value");
      Put_Line ("  k      Discrete variate value (non-negative integer)");
      Put_Line ("  p      Probability for inverse CDF  (0 < p < 1)");
      New_Line;
      Put_Line ("Distribution prefixes:");
      Put_Line ("  Z  Standard Normal (fixed mu=0, sigma=1)");
      Put_Line ("  N  Binomial  (n trials, prob success probability)");
      Put_Line ("  U  Uniform on [lo, hi]");
      Put_Line ("  E  Exponential with rate parameter");
      Put_Line ("  B  Beta  (shape parameters a, b)");
      Put_Line ("  P  Poisson  (mean lambda)");
      Put_Line ("  G  Gamma  (shape, rate)");
      Put_Line ("  X  Chi-square  (df degrees of freedom)");
      Put_Line ("  T  Student's t  (df degrees of freedom)");
      Put_Line ("  F  F distribution  (df1, df2 degrees of freedom)");
      Put_Line ("  M  Binomial  (n trials, prob success probability)");
      Put_Line ("  W  Weibull  (scale, shape)");
      Put_Line ("  L  Laplace / double-exponential  (loc, scale)");
      New_Line;
      Put_Line ("Use HELP <prefix>DF for full details on each family.");
   end Help_DISTRIBUTIONS;

   procedure Help_ZDF is
   begin
      Put_Line ("Normal distribution (mu and sigma are optional; default mu=0, sigma=1):");
      Put_Line ("  ZDF(x [, mu, sigma])   probability density at x");
      Put_Line ("  ZCF(x [, mu, sigma])   cumulative probability P(X <= x)");
      Put_Line ("  ZIF(p [, mu, sigma])   quantile: x such that P(X <= x) = p  (0 < p < 1)");
      Put_Line ("  ZRN([mu, sigma])       random variate");
   end Help_ZDF;

   procedure Help_NDF is
   begin
      Put_Line ("Binomial distribution (discrete):");
      Put_Line ("  NDF(k, n, prob)   probability mass P(X = k)  (k = 0, 1, ..., n)");
      Put_Line ("  NCF(k, n, prob)   cumulative probability P(X <= k)");
      Put_Line ("  NIF(p, n, prob)   quantile  (0 < p < 1)");
      Put_Line ("  NRN(n, prob)      random variate");
      Put_Line ("  n: number of trials (positive integer)");
      Put_Line ("  prob: success probability per trial (0 <= prob <= 1)");
      Put_Line ("See also: MDF/MCF/MIF/MRN (identical functions, alternative prefix).");
   end Help_NDF;

   procedure Help_UDF is
   begin
      Put_Line ("Uniform distribution on [lo, hi]:");
      Put_Line ("  UDF(x, lo, hi)   probability density (1/(hi-lo) for lo <= x <= hi)");
      Put_Line ("  UCF(x, lo, hi)   cumulative probability P(X <= x)");
      Put_Line ("  UIF(p, lo, hi)   quantile  (0 < p < 1)");
      Put_Line ("  URN(lo, hi)      random variate on [lo, hi]");
      Put_Line ("  URN()            random variate on [0, 1] (default bounds)");
      Put_Line ("  lo, hi: interval bounds (lo < hi)");
   end Help_UDF;

   procedure Help_EDF is
   begin
      Put_Line ("Exponential distribution:");
      Put_Line ("  EDF(x, rate)   probability density (rate*exp(-rate*x), x >= 0)");
      Put_Line ("  ECF(x, rate)   cumulative probability P(X <= x)");
      Put_Line ("  EIF(p, rate)   quantile  (0 < p < 1)");
      Put_Line ("  ERN(rate)      random variate");
      Put_Line ("  rate: rate parameter lambda (rate > 0); mean = 1/rate");
   end Help_EDF;

   procedure Help_BDF is
   begin
      Put_Line ("Beta distribution on [0, 1]:");
      Put_Line ("  BDF(x, a, b)   probability density");
      Put_Line ("  BCF(x, a, b)   cumulative probability P(X <= x)");
      Put_Line ("  BIF(p, a, b)   quantile  (0 < p < 1)");
      Put_Line ("  BRN(a, b)      random variate");
      Put_Line ("  a, b: shape parameters (both > 0)");
   end Help_BDF;

   procedure Help_PDF is
   begin
      Put_Line ("Poisson distribution (discrete):");
      Put_Line ("  PDF(k, lambda)   probability mass P(X = k)  (k non-negative integer)");
      Put_Line ("  PCF(k, lambda)   cumulative probability P(X <= k)");
      Put_Line ("  PIF(p, lambda)   quantile  (0 < p < 1)");
      Put_Line ("  PRN(lambda)      random variate");
      Put_Line ("  lambda: mean arrival rate (lambda > 0)");
   end Help_PDF;

   procedure Help_GDF is
   begin
      Put_Line ("Gamma distribution:");
      Put_Line ("  GDF(x, shape, rate)   probability density (x >= 0)");
      Put_Line ("  GCF(x, shape, rate)   cumulative probability P(X <= x)");
      Put_Line ("  GIF(p, shape, rate)   quantile  (0 < p < 1)");
      Put_Line ("  GRN(shape, rate)      random variate");
      Put_Line ("  shape: shape parameter k (> 0); rate: rate parameter (> 0)");
      Put_Line ("  mean = shape/rate;  variance = shape/rate^2");
   end Help_GDF;

   procedure Help_XDF is
   begin
      Put_Line ("Chi-square distribution:");
      Put_Line ("  XDF(x, df)   probability density (x >= 0)");
      Put_Line ("  XCF(x, df)   cumulative probability P(X <= x)");
      Put_Line ("  XIF(p, df)   quantile  (0 < p < 1)");
      Put_Line ("  XRN(df)      random variate");
      Put_Line ("  df: degrees of freedom (positive integer)");
      Put_Line ("  mean = df;  variance = 2*df");
   end Help_XDF;

   procedure Help_TDF is
   begin
      Put_Line ("Student's t distribution:");
      Put_Line ("  TDF(x, df)   probability density");
      Put_Line ("  TCF(x, df)   cumulative probability P(T <= x)");
      Put_Line ("  TIF(p, df)   quantile  (0 < p < 1)");
      Put_Line ("  TRN(df)      random variate");
      Put_Line ("  df: degrees of freedom (df > 0; need not be an integer)");
   end Help_TDF;

   procedure Help_FDF is
   begin
      Put_Line ("F distribution:");
      Put_Line ("  FDF(x, df1, df2)   probability density (x >= 0)");
      Put_Line ("  FCF(x, df1, df2)   cumulative probability P(F <= x)");
      Put_Line ("  FIF(p, df1, df2)   quantile  (0 < p < 1)");
      Put_Line ("  FRN(df1, df2)      random variate");
      Put_Line ("  df1: numerator degrees of freedom; df2: denominator degrees of freedom");
      Put_Line ("  (both > 0; need not be integers)");
   end Help_FDF;

   procedure Help_MDF is
   begin
      Put_Line ("Binomial distribution (discrete):");
      Put_Line ("  MDF(k, n, prob)   probability mass P(X = k)  (k = 0, 1, ..., n)");
      Put_Line ("  MCF(k, n, prob)   cumulative probability P(X <= k)");
      Put_Line ("  MIF(p, n, prob)   quantile  (0 < p < 1)");
      Put_Line ("  MRN(n, prob)      random variate");
      Put_Line ("  n: number of trials (positive integer)");
      Put_Line ("  prob: success probability per trial (0 <= prob <= 1)");
      Put_Line ("See also: NDF/NCF/NIF/NRN (identical functions, alternative prefix).");
   end Help_MDF;

   procedure Help_WDF is
   begin
      Put_Line ("Weibull distribution:");
      Put_Line ("  WDF(x, scale, shape)   probability density (x >= 0)");
      Put_Line ("  WCF(x, scale, shape)   cumulative probability P(X <= x)");
      Put_Line ("  WIF(p, scale, shape)   quantile  (0 < p < 1)");
      Put_Line ("  WRN(scale, shape)      random variate");
      Put_Line ("  scale: scale parameter lambda (> 0); shape: shape parameter k (> 0)");
      Put_Line ("  Exponential is the special case shape = 1.");
   end Help_WDF;

   procedure Help_LDF is
   begin
      Put_Line ("Logistic distribution (standard, location=0, scale=1):");
      Put_Line ("  LDF(x)   probability density at x");
      Put_Line ("  LCF(x)   cumulative probability P(X <= x)");
      Put_Line ("  LIF(p)   quantile / inverse CDF  (0 < p < 1)");
      Put_Line ("  LRN      random variate");
   end Help_LDF;

   -- ==========================================================================
   --  Dispatch table
   -- ==========================================================================

   --  Each entry maps one lookup key to a handler procedure.
   --  Aliases (e.g. QUIT/END, LAG/LAGC$) share the same handler.
   --  In_Cmd / In_Func control which section the topic appears in for HELP /ALL.

   type Help_Proc is access procedure;

   type Help_Entry is record
      Key     : access constant String;
      Handler : Help_Proc;
      In_Cmd  : Boolean;   --  include in COMMAND REFERENCE section of /ALL
      In_Func : Boolean;   --  include in FUNCTION REFERENCE section of /ALL
   end record;

   --  Key constants (aliased so 'Access can be taken)
   K_USE          : aliased constant String := "USE";
   K_SAVE         : aliased constant String := "SAVE";
   K_WRITE        : aliased constant String := "WRITE";
   K_SUBMIT       : aliased constant String := "SUBMIT";
   K_SYSTEM       : aliased constant String := "SYSTEM";
   K_PRINT        : aliased constant String := "PRINT";
   K_RUN          : aliased constant String := "RUN";
   K_LET          : aliased constant String := "LET";
   K_SET          : aliased constant String := "SET";
   K_UNSET        : aliased constant String := "UNSET";
   K_ARRAY        : aliased constant String := "ARRAY";
   K_DIM          : aliased constant String := "DIM";
   K_BY           : aliased constant String := "BY";
   K_VANDALIZE    : aliased constant String := "VANDALIZE";
   K_SORT         : aliased constant String := "SORT";
   K_NEW          : aliased constant String := "NEW";
   K_LIST         : aliased constant String := "LIST";
   K_DISPLAY      : aliased constant String := "DISPLAY";
   K_NAMES        : aliased constant String := "NAMES";
   K_DELETE       : aliased constant String := "DELETE";
   K_HOLD         : aliased constant String := "HOLD";
   K_UNHOLD       : aliased constant String := "UNHOLD";
   K_KEEP         : aliased constant String := "KEEP";
   K_DROP         : aliased constant String := "DROP";
   K_RENAME       : aliased constant String := "RENAME";
   K_IF           : aliased constant String := "IF";
   K_ELSEIF       : aliased constant String := "ELSEIF";
   K_SELECT       : aliased constant String := "SELECT";
   K_FOR          : aliased constant String := "FOR";
   K_WHILE        : aliased constant String := "WHILE";
   K_REPEAT       : aliased constant String := "REPEAT";
   K_OUTPUT       : aliased constant String := "OUTPUT";
   K_ECHO         : aliased constant String := "ECHO";
   K_DIGITS       : aliased constant String := "DIGITS";
   K_FPATH        : aliased constant String := "FPATH";
   K_RSEED        : aliased constant String := "RSEED";
   K_HELP         : aliased constant String := "HELP";
   K_QUIT         : aliased constant String := "QUIT";
   K_END          : aliased constant String := "END";
   K_OPTIONS      : aliased constant String := "OPTIONS";
   K_EXECUTION    : aliased constant String := "EXECUTION";
   K_CONCEPTS     : aliased constant String := "CONCEPTS";
   K_BREAK        : aliased constant String := "BREAK";
   K_DEBUGGER     : aliased constant String := "DEBUGGER";
   K_DEBUG        : aliased constant String := "DEBUG";
   K_ABS          : aliased constant String := "ABS";
   K_SQRT         : aliased constant String := "SQRT";
   K_LOG          : aliased constant String := "LOG";
   K_LOG10        : aliased constant String := "LOG10";
   K_EXP          : aliased constant String := "EXP";
   K_ROUND        : aliased constant String := "ROUND";
   K_CEIL         : aliased constant String := "CEIL";
   K_FLOOR        : aliased constant String := "FLOOR";
   K_INT          : aliased constant String := "INT";
   K_FIX          : aliased constant String := "FIX";
   K_IP           : aliased constant String := "IP";
   K_FP           : aliased constant String := "FP";
   K_LN           : aliased constant String := "LN";
   K_LOGE         : aliased constant String := "LOGE";
   K_LOG2         : aliased constant String := "LOG2";
   K_CLG          : aliased constant String := "CLG";
   K_LGT          : aliased constant String := "LGT";
   K_MOD          : aliased constant String := "MOD";
   K_SQR          : aliased constant String := "SQR";
   K_SGN          : aliased constant String := "SGN";
   K_SIN          : aliased constant String := "SIN";
   K_COS          : aliased constant String := "COS";
   K_TAN          : aliased constant String := "TAN";
   K_ATN          : aliased constant String := "ATN";
   K_ATAN2        : aliased constant String := "ATAN2";
   K_ARCSIN       : aliased constant String := "ARCSIN";
   K_ARCCOS       : aliased constant String := "ARCCOS";
   K_ARCTAN       : aliased constant String := "ARCTAN";
   K_COT          : aliased constant String := "COT";
   K_CSC          : aliased constant String := "CSC";
   K_SEC          : aliased constant String := "SEC";
   K_SINH         : aliased constant String := "SINH";
   K_HSN          : aliased constant String := "HSN";
   K_COSH         : aliased constant String := "COSH";
   K_HCS          : aliased constant String := "HCS";
   K_TANH         : aliased constant String := "TANH";
   K_HTN          : aliased constant String := "HTN";
   K_DEG          : aliased constant String := "DEG";
   K_DEGREE       : aliased constant String := "DEGREE";
   K_SIND         : aliased constant String := "SIND";
   K_COSD         : aliased constant String := "COSD";
   K_TAND         : aliased constant String := "TAND";
   K_ATND         : aliased constant String := "ATND";
   K_ATAN2D       : aliased constant String := "ATAN2D";
   K_LEN          : aliased constant String := "LEN";
   K_LEFTS        : aliased constant String := "LEFT$";
   K_RIGHTS       : aliased constant String := "RIGHT$";
   K_MIDS         : aliased constant String := "MID$";
   K_SEGS         : aliased constant String := "SEG$";
   K_FRAC         : aliased constant String := "FRAC";
   K_TRIMS        : aliased constant String := "TRIM$";
   K_LTRIMS       : aliased constant String := "LTRIM$";
   K_RTRIMS       : aliased constant String := "RTRIM$";
   K_UCASES       : aliased constant String := "UCASE$";
   K_UPPERS       : aliased constant String := "UPPER$";
   K_LCASES       : aliased constant String := "LCASE$";
   K_LOWERS       : aliased constant String := "LOWER$";
   K_POS          : aliased constant String := "POS";
   K_INSTR        : aliased constant String := "INSTR";
   K_CHRS         : aliased constant String := "CHR$";
   K_ASCII        : aliased constant String := "ASCII";
   K_ASC          : aliased constant String := "ASC";
   K_STRS         : aliased constant String := "STR$";
   K_VAL          : aliased constant String := "VAL";
   K_NUMS         : aliased constant String := "NUM$";
   K_NUM          : aliased constant String := "NUM";
   K_HEXS         : aliased constant String := "HEX$";
   K_HEX          : aliased constant String := "HEX";
   K_OCTS         : aliased constant String := "OCT$";
   K_BINS         : aliased constant String := "BIN$";
   K_RECNO        : aliased constant String := "RECNO";
   K_BOF          : aliased constant String := "BOF";
   K_EOF          : aliased constant String := "EOF";
   K_BOG          : aliased constant String := "BOG";
   K_EOG          : aliased constant String := "EOG";
   K_LAG          : aliased constant String := "LAG";
   K_LAGCS        : aliased constant String := "LAGC$";
   K_NEXT         : aliased constant String := "NEXT";
   K_NEXTCS       : aliased constant String := "NEXTC$";
   K_OBS          : aliased constant String := "OBS";
   K_OBSCS        : aliased constant String := "OBSC$";
   K_MISSING      : aliased constant String := "MISSING";
   K_INF          : aliased constant String := "INF";
   K_RAN          : aliased constant String := "RAN";
   K_RANDOM       : aliased constant String := "RANDOM";
   K_RND          : aliased constant String := "RND";
   K_DATES        : aliased constant String := "DATE$";
   K_TIMES        : aliased constant String := "TIME$";
   K_SHELL        : aliased constant String := "SHELL";
   K_FALSE        : aliased constant String := "FALSE";
   K_TRUE         : aliased constant String := "TRUE";
   K_ERR          : aliased constant String := "ERR";
   K_ERL          : aliased constant String := "ERL";
   K_SUM          : aliased constant String := "SUM";
   K_MEAN         : aliased constant String := "MEAN";
   K_GMEAN        : aliased constant String := "GMEAN";
   K_HMEAN        : aliased constant String := "HMEAN";
   K_STD          : aliased constant String := "STD";
   K_VAR          : aliased constant String := "VAR";
   K_MIN          : aliased constant String := "MIN";
   K_MAX          : aliased constant String := "MAX";
   K_MEDIAN       : aliased constant String := "MEDIAN";
   K_N            : aliased constant String := "N";
   K_NMISS        : aliased constant String := "NMISS";
   K_DISTRIBUTIONS : aliased constant String := "DISTRIBUTIONS";
   K_DIST         : aliased constant String := "DIST";
   K_ZDF          : aliased constant String := "ZDF";
   K_ZCF          : aliased constant String := "ZCF";
   K_ZIF          : aliased constant String := "ZIF";
   K_ZRN          : aliased constant String := "ZRN";
   K_NDF          : aliased constant String := "NDF";
   K_NCF          : aliased constant String := "NCF";
   K_NIF          : aliased constant String := "NIF";
   K_NRN          : aliased constant String := "NRN";
   K_UDF          : aliased constant String := "UDF";
   K_UCF          : aliased constant String := "UCF";
   K_UIF          : aliased constant String := "UIF";
   K_URN          : aliased constant String := "URN";
   K_EDF          : aliased constant String := "EDF";
   K_ECF          : aliased constant String := "ECF";
   K_EIF          : aliased constant String := "EIF";
   K_ERN          : aliased constant String := "ERN";
   K_BDF          : aliased constant String := "BDF";
   K_BCF          : aliased constant String := "BCF";
   K_BIF          : aliased constant String := "BIF";
   K_PDF          : aliased constant String := "PDF";
   K_PCF          : aliased constant String := "PCF";
   K_PIF          : aliased constant String := "PIF";
   K_PRN          : aliased constant String := "PRN";
   K_GDF          : aliased constant String := "GDF";
   K_GCF          : aliased constant String := "GCF";
   K_GIF          : aliased constant String := "GIF";
   K_GRN          : aliased constant String := "GRN";
   K_XDF          : aliased constant String := "XDF";
   K_XCF          : aliased constant String := "XCF";
   K_XIF          : aliased constant String := "XIF";
   K_XRN          : aliased constant String := "XRN";
   K_TDF          : aliased constant String := "TDF";
   K_TCF          : aliased constant String := "TCF";
   K_TIF          : aliased constant String := "TIF";
   K_TRN          : aliased constant String := "TRN";
   K_FDF          : aliased constant String := "FDF";
   K_FCF          : aliased constant String := "FCF";
   K_FIF          : aliased constant String := "FIF";
   K_FRN          : aliased constant String := "FRN";
   K_MDF          : aliased constant String := "MDF";
   K_MCF          : aliased constant String := "MCF";
   K_MIF          : aliased constant String := "MIF";
   K_WDF          : aliased constant String := "WDF";
   K_WCF          : aliased constant String := "WCF";
   K_WIF          : aliased constant String := "WIF";
   K_WRN          : aliased constant String := "WRN";
   K_LDF          : aliased constant String := "LDF";
   K_LCF          : aliased constant String := "LCF";
   K_LIF          : aliased constant String := "LIF";
   K_LRN          : aliased constant String := "LRN";

   --  C = appears in COMMAND REFERENCE for /ALL
   --  F = appears in FUNCTION REFERENCE for /ALL
   --  Aliases have In_Cmd/In_Func = False to avoid duplicate output in /ALL.
   C : constant Boolean := True;
   F : constant Boolean := True;
   N : constant Boolean := False;

   Help_Table : constant array (Positive range <>) of Help_Entry := (
      --  Commands
      (K_USE'Access,      Help_USE'Access,      C, N),
      (K_SAVE'Access,     Help_SAVE'Access,     C, N),
      (K_WRITE'Access,    Help_WRITE'Access,    C, N),
      (K_SUBMIT'Access,   Help_SUBMIT'Access,   C, N),
      (K_SYSTEM'Access,   Help_SYSTEM'Access,   C, N),
      (K_PRINT'Access,    Help_PRINT'Access,    C, N),
      (K_RUN'Access,      Help_RUN'Access,      C, N),
      (K_LET'Access,      Help_LET'Access,      C, N),
      (K_SET'Access,      Help_SET'Access,      C, N),
      (K_UNSET'Access,    Help_UNSET'Access,    C, N),
      (K_ARRAY'Access,    Help_ARRAY'Access,    C, N),
      (K_DIM'Access,      Help_DIM'Access,      C, N),
      (K_BY'Access,       Help_BY'Access,       C, N),
      (K_VANDALIZE'Access, Help_VANDALIZE'Access, C, N),
      (K_SORT'Access,     Help_SORT'Access,     C, N),
      (K_NEW'Access,      Help_NEW'Access,      C, N),
      (K_LIST'Access,     Help_LIST'Access,     C, N),
      (K_DISPLAY'Access,  Help_DISPLAY'Access,  C, N),
      (K_NAMES'Access,    Help_NAMES'Access,    C, N),
      (K_DELETE'Access,   Help_DELETE'Access,   C, N),
      (K_BREAK'Access,    Help_BREAK'Access,    C, N),
      (K_HOLD'Access,     Help_HOLD'Access,     C, N),
      (K_UNHOLD'Access,   Help_UNHOLD'Access,   C, N),
      (K_KEEP'Access,     Help_KEEP'Access,     C, N),
      (K_DROP'Access,     Help_DROP'Access,     C, N),
      (K_RENAME'Access,   Help_RENAME'Access,   C, N),
      (K_IF'Access,       Help_IF'Access,       C, N),
      (K_ELSEIF'Access,   Help_IF'Access,       N, N),   --  alias
      (K_SELECT'Access,   Help_SELECT'Access,   C, N),
      (K_FOR'Access,      Help_FOR'Access,      C, N),
      (K_WHILE'Access,    Help_WHILE'Access,    C, N),
      (K_REPEAT'Access,   Help_REPEAT'Access,   C, N),
      (K_OUTPUT'Access,   Help_OUTPUT'Access,   C, N),
      (K_ECHO'Access,     Help_ECHO'Access,     C, N),
      (K_DIGITS'Access,   Help_DIGITS'Access,   C, N),
      (K_FPATH'Access,    Help_FPATH'Access,    C, N),
      (K_RSEED'Access,    Help_RSEED'Access,    C, N),
      (K_HELP'Access,     Help_HELP'Access,     C, N),
      (K_QUIT'Access,     Help_QUIT'Access,     C, N),
      (K_END'Access,      Help_QUIT'Access,     N, N),   --  alias
      (K_OPTIONS'Access,  Help_OPTIONS'Access,  C, N),
      (K_EXECUTION'Access, Help_EXECUTION'Access, C, N),
      (K_CONCEPTS'Access,  Help_CONCEPTS'Access,  C, N),
      (K_DEBUGGER'Access, Help_DEBUGGER'Access,  C, N),
      (K_DEBUG'Access,    Help_DEBUGGER'Access,  N, N),   --  alias
      --  Math functions
      (K_ABS'Access,      Help_ABS'Access,      N, F),
      (K_SQRT'Access,     Help_SQRT'Access,     N, F),
      (K_SQR'Access,      Help_SQRT'Access,     N, N),   --  BW BASIC alias
      (K_SGN'Access,      Help_SGN'Access,      N, F),
      (K_LOG'Access,      Help_LOG'Access,      N, F),
      (K_LOG10'Access,    Help_LOG10'Access,    N, F),
      (K_EXP'Access,      Help_EXP'Access,      N, F),
      (K_ROUND'Access,    Help_ROUND'Access,    N, F),
      (K_CEIL'Access,     Help_CEIL'Access,     N, F),
      (K_FLOOR'Access,    Help_FLOOR'Access,    N, F),
      (K_INT'Access,      Help_INT'Access,      N, F),
      (K_FIX'Access,      Help_FIX'Access,      N, F),
      (K_IP'Access,       Help_FIX'Access,      N, N),   --  alias
      (K_FP'Access,       Help_FP'Access,       N, F),
      (K_FRAC'Access,     Help_FRAC'Access,     N, N),   --  alias
      (K_LN'Access,       Help_LN'Access,       N, F),
      (K_LOGE'Access,     Help_LN'Access,       N, N),   --  alias
      (K_LOG2'Access,     Help_LOG2'Access,     N, F),
      (K_CLG'Access,      Help_CLG'Access,      N, F),
      (K_LGT'Access,      Help_CLG'Access,      N, N),   --  alias
      (K_MOD'Access,      Help_MOD'Access,      N, F),
      --  Trig (radians)
      (K_SIN'Access,      Help_SIN'Access,      N, F),
      (K_COS'Access,      Help_COS'Access,      N, F),
      (K_TAN'Access,      Help_TAN'Access,      N, F),
      (K_ATN'Access,      Help_ATN'Access,      N, F),
      (K_ATAN2'Access,    Help_ATAN2'Access,    N, F),
      (K_ARCSIN'Access,   Help_ARCSIN'Access,   N, F),
      (K_ARCCOS'Access,   Help_ARCCOS'Access,   N, F),
      (K_ARCTAN'Access,   Help_ARCTAN'Access,   N, F),
      (K_COT'Access,      Help_COT'Access,      N, F),
      (K_CSC'Access,      Help_CSC'Access,      N, F),
      (K_SEC'Access,      Help_SEC'Access,      N, F),
      (K_SINH'Access,     Help_SINH'Access,     N, F),
      (K_HSN'Access,      Help_SINH'Access,     N, N),   --  alias
      (K_COSH'Access,     Help_COSH'Access,     N, F),
      (K_HCS'Access,      Help_COSH'Access,     N, N),   --  alias
      (K_TANH'Access,     Help_TANH'Access,     N, F),
      (K_HTN'Access,      Help_TANH'Access,     N, N),   --  alias
      (K_DEG'Access,      Help_DEG'Access,      N, F),
      (K_DEGREE'Access,   Help_DEG'Access,      N, N),   --  alias
      --  Trig (degrees)
      (K_SIND'Access,     Help_SIND'Access,     N, F),
      (K_COSD'Access,     Help_COSD'Access,     N, F),
      (K_TAND'Access,     Help_TAND'Access,     N, F),
      (K_ATND'Access,     Help_ATND'Access,     N, F),
      (K_ATAN2D'Access,   Help_ATAN2D'Access,   N, F),
      --  String functions
      (K_LEN'Access,      Help_LEN'Access,      N, F),
      (K_LEFTS'Access,    Help_LEFTS'Access,    N, F),
      (K_RIGHTS'Access,   Help_RIGHTS'Access,   N, F),
      (K_MIDS'Access,     Help_MIDS'Access,     N, F),
      (K_SEGS'Access,     Help_SEGS'Access,     N, F),
      (K_TRIMS'Access,    Help_TRIMS'Access,    N, F),
      (K_LTRIMS'Access,   Help_LTRIMS'Access,   N, F),
      (K_RTRIMS'Access,   Help_RTRIMS'Access,   N, F),
      (K_UCASES'Access,   Help_UCASES'Access,   N, F),
      (K_UPPERS'Access,   Help_UCASES'Access,   N, N),   --  alias
      (K_LCASES'Access,   Help_LCASES'Access,   N, F),
      (K_LOWERS'Access,   Help_LCASES'Access,   N, N),   --  alias
      (K_POS'Access,      Help_POS'Access,      N, F),
      (K_INSTR'Access,    Help_INSTR'Access,    N, F),
      (K_CHRS'Access,     Help_CHRS'Access,     N, F),
      (K_ASCII'Access,    Help_ASCII'Access,    N, F),
      (K_ASC'Access,      Help_ASCII'Access,    N, N),   --  BW BASIC alias
      (K_STRS'Access,     Help_STRS'Access,     N, F),
      (K_VAL'Access,      Help_VAL'Access,      N, F),
      (K_NUMS'Access,     Help_NUMS'Access,     N, F),
      (K_NUM'Access,      Help_NUM'Access,      N, F),
      --  Base conversion
      (K_HEXS'Access,     Help_HEXS'Access,     N, F),
      (K_HEX'Access,      Help_HEX'Access,      N, F),
      (K_OCTS'Access,     Help_OCTS'Access,     N, F),
      (K_BINS'Access,     Help_BINS'Access,     N, F),
      --  Record navigation
      (K_RECNO'Access,    Help_RECNO'Access,    N, F),
      (K_BOF'Access,      Help_BOF'Access,      N, F),
      (K_EOF'Access,      Help_EOF'Access,      N, F),
      (K_BOG'Access,      Help_BOG'Access,      N, F),
      (K_EOG'Access,      Help_EOG'Access,      N, F),
      (K_LAG'Access,      Help_LAG'Access,      N, F),
      (K_LAGCS'Access,    Help_LAG'Access,      N, N),   --  alias
      (K_NEXT'Access,     Help_NEXT'Access,     N, F),
      (K_NEXTCS'Access,   Help_NEXT'Access,     N, N),   --  alias
      (K_OBS'Access,      Help_OBS'Access,      N, F),
      (K_OBSCS'Access,    Help_OBS'Access,      N, N),   --  alias
      --  Special functions
      (K_MISSING'Access,  Help_MISSING'Access,  N, F),
      (K_INF'Access,      Help_INF'Access,      N, F),
      (K_RAN'Access,      Help_RAN'Access,      N, F),
      (K_RANDOM'Access,   Help_RAN'Access,      N, N),   --  alias
      (K_RND'Access,      Help_RAN'Access,      N, N),   --  BW BASIC alias
      (K_DATES'Access,    Help_DATES'Access,    N, F),
      (K_TIMES'Access,    Help_TIMES'Access,    N, F),
      (K_SHELL'Access,    Help_SHELL'Access,    N, F),
      (K_FALSE'Access,    Help_FALSE'Access,    N, F),
      (K_TRUE'Access,     Help_TRUE'Access,     N, F),
      (K_ERR'Access,      Help_ERR'Access,      N, F),
      (K_ERL'Access,      Help_ERL'Access,      N, F),
      --  Aggregate functions
      (K_SUM'Access,      Help_SUM'Access,      N, F),
      (K_MEAN'Access,     Help_MEAN'Access,     N, F),
      (K_GMEAN'Access,    Help_GMEAN'Access,    N, F),
      (K_HMEAN'Access,    Help_HMEAN'Access,    N, F),
      (K_STD'Access,      Help_STD'Access,      N, F),
      (K_VAR'Access,      Help_VAR'Access,      N, F),
      (K_MIN'Access,      Help_MIN'Access,      N, F),
      (K_MAX'Access,      Help_MAX'Access,      N, F),
      (K_MEDIAN'Access,   Help_MEDIAN'Access,   N, F),
      (K_N'Access,        Help_N'Access,        N, F),
      (K_NMISS'Access,    Help_NMISS'Access,    N, F),
      --  Statistical distributions
      (K_DISTRIBUTIONS'Access, Help_DISTRIBUTIONS'Access, N, F),
      (K_DIST'Access,     Help_DISTRIBUTIONS'Access, N, N),   --  alias
      (K_ZDF'Access,      Help_ZDF'Access,      N, F),
      (K_ZCF'Access,      Help_ZDF'Access,      N, N),
      (K_ZIF'Access,      Help_ZDF'Access,      N, N),
      (K_ZRN'Access,      Help_ZDF'Access,      N, N),
      (K_NDF'Access,      Help_NDF'Access,      N, F),
      (K_NCF'Access,      Help_NDF'Access,      N, N),
      (K_NIF'Access,      Help_NDF'Access,      N, N),
      (K_NRN'Access,      Help_NDF'Access,      N, N),
      (K_UDF'Access,      Help_UDF'Access,      N, F),
      (K_UCF'Access,      Help_UDF'Access,      N, N),
      (K_UIF'Access,      Help_UDF'Access,      N, N),
      (K_URN'Access,      Help_UDF'Access,      N, N),
      (K_EDF'Access,      Help_EDF'Access,      N, F),
      (K_ECF'Access,      Help_EDF'Access,      N, N),
      (K_EIF'Access,      Help_EDF'Access,      N, N),
      (K_ERN'Access,      Help_EDF'Access,      N, N),
      (K_BDF'Access,      Help_BDF'Access,      N, F),
      (K_BCF'Access,      Help_BDF'Access,      N, N),
      (K_BIF'Access,      Help_BDF'Access,      N, N),
      (K_PDF'Access,      Help_PDF'Access,      N, F),
      (K_PCF'Access,      Help_PDF'Access,      N, N),
      (K_PIF'Access,      Help_PDF'Access,      N, N),
      (K_PRN'Access,      Help_PDF'Access,      N, N),
      (K_GDF'Access,      Help_GDF'Access,      N, F),
      (K_GCF'Access,      Help_GDF'Access,      N, N),
      (K_GIF'Access,      Help_GDF'Access,      N, N),
      (K_GRN'Access,      Help_GDF'Access,      N, N),
      (K_XDF'Access,      Help_XDF'Access,      N, F),
      (K_XCF'Access,      Help_XDF'Access,      N, N),
      (K_XIF'Access,      Help_XDF'Access,      N, N),
      (K_XRN'Access,      Help_XDF'Access,      N, N),
      (K_TDF'Access,      Help_TDF'Access,      N, F),
      (K_TCF'Access,      Help_TDF'Access,      N, N),
      (K_TIF'Access,      Help_TDF'Access,      N, N),
      (K_TRN'Access,      Help_TDF'Access,      N, N),
      (K_FDF'Access,      Help_FDF'Access,      N, F),
      (K_FCF'Access,      Help_FDF'Access,      N, N),
      (K_FIF'Access,      Help_FDF'Access,      N, N),
      (K_FRN'Access,      Help_FDF'Access,      N, N),
      (K_MDF'Access,      Help_MDF'Access,      N, F),
      (K_MCF'Access,      Help_MDF'Access,      N, N),
      (K_MIF'Access,      Help_MDF'Access,      N, N),
      (K_WDF'Access,      Help_WDF'Access,      N, F),
      (K_WCF'Access,      Help_WDF'Access,      N, N),
      (K_WIF'Access,      Help_WDF'Access,      N, N),
      (K_WRN'Access,      Help_WDF'Access,      N, N),
      (K_LDF'Access,      Help_LDF'Access,      N, F),
      (K_LCF'Access,      Help_LDF'Access,      N, N),
      (K_LIF'Access,      Help_LDF'Access,      N, N),
      (K_LRN'Access,      Help_LDF'Access,      N, N)
   );

   -- ==========================================================================
   --  Dispatcher
   -- ==========================================================================

   procedure Print_Help (Topic : String) is
      T : constant String := To_Upper (Topic);
   begin
      if T = "" then
         Help_Index;
         return;
      end if;

      if T = "/ALL" then
         Put_Line ("=== COMMAND REFERENCE ===");
         for E of Help_Table loop
            if E.In_Cmd then
               E.Handler.all;
               New_Line;
            end if;
         end loop;
         Put_Line ("=== FUNCTION REFERENCE ===");
         for E of Help_Table loop
            if E.In_Func then
               E.Handler.all;
               New_Line;
            end if;
         end loop;
         return;
      end if;

      for E of Help_Table loop
         if E.Key.all = T then
            E.Handler.all;
            return;
         end if;
      end loop;

      Put_Line ("Help topic not found: " & T);
      Put_Line ("Type HELP for a list of commands and functions.");
   end Print_Help;

end SData.Help;