with SData.Table;     use SData.Table;
with SData.Values;    use SData.Values;
with SData.Variables; use SData.Variables;
with SData.Evaluator; use SData.Evaluator;
with GNAT.Strings; use GNAT.Strings;
with SData.System;
with SData.Statistics;
with SData.Parser; use SData.Parser;
with Ada.Streams.Stream_IO;
with Ada.Exceptions;
with SData.File_IO;
with SData.Config;    use SData.Config;
with SData.IO;        use SData.IO;
with Ada.Characters.Handling; use Ada.Characters.Handling;
with Ada.Containers.Indefinite_Hashed_Sets;
with Ada.Containers.Vectors;
with Ada.Strings.Hash;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body SData.Interpreter is

   procedure Set_Interactive (Val : Boolean) is
   begin
      SData.IO.Set_Interactive (Val);
   end Set_Interactive;

   --  Forward declarations for internal logic.
   procedure Execute_Statement (Stmt : Statement_Access);
   procedure Execute_List (List : Statement_Access; Boundary : Statement_Access := null);
   
   function Full_Path (Path : String; Category : String) return String;

   --  Set to track columns provided by the input file (to skip reset).
   package Name_Sets is new Ada.Containers.Indefinite_Hashed_Sets
     (Element_Type => String,
      Hash         => Ada.Strings.Hash,
      Equivalent_Elements => "=");
   Input_File_Columns : Name_Sets.Set;

   --  Set of script files currently in the SUBMIT execution chain (for cycle detection).
   Submit_Chain : Name_Sets.Set;

   --  Column modifications state.
   type Column_Mod_Kind is (Mod_Keep, Mod_Drop);
   type Column_Mod_Node;
   type Column_Mod_List is access Column_Mod_Node;
   type Column_Mod_Node is record
      Kind : Column_Mod_Kind;
      Name : String (1 .. 32);
      Len  : Natural;
      Next : Column_Mod_List;
   end record;

   Pending_Mods : Column_Mod_List := null;

   --  State for Data Step record processing.
   Current_Record_Deleted : Boolean := False;
   

   -- For BY statement processing
   package By_Group_Names is new Ada.Containers.Vectors (Index_Type => Positive, Element_Type => Unbounded_String);
   Current_By_Vars : By_Group_Names.Vector;
   
   -- Global program for REPL mode.
   Active_Program_Head : Statement_Access := null;
   Active_Program_Tail : Statement_Access := null;

   procedure Add_To_Active_Program (Stmt : Statement_Access) is
   begin
      if Stmt = null then return; end if;
      Stmt.Next := null;
      if Active_Program_Head = null then
         Active_Program_Head := Stmt;
         Active_Program_Tail := Stmt;
      else
         Active_Program_Tail.Next := Stmt;
         Active_Program_Tail := Stmt;
      end if;
   end Add_To_Active_Program;

   procedure Clear_Active_Program is
   begin
      Active_Program_Head := null;
      Active_Program_Tail := null;
   end Clear_Active_Program;

   procedure Run_Active_Program is
   begin
      if Active_Program_Head /= null then
         declare
            Prog    : constant Statement_Access := Active_Program_Head;
            Tail    : Statement_Access := Prog;
            Run_Cap : constant Statement_Access := new Statement (Stmt_RUN);
         begin
            --  Cap the chain with a synthetic Stmt_RUN so that Execute's
            --  outer loop calls Run_One_Step on the queued deferred
            --  statements.  The program is NOT cleared — it persists so
            --  that subsequent RUN commands re-execute the same program.
            --  Only NEW, USE, or REPEAT should replace the program.
            while Tail.Next /= null loop
               Tail := Tail.Next;
            end loop;
            Tail.Next := Run_Cap;
            Execute (Prog);
            --  Remove the synthetic cap so the chain is clean for next time.
            Tail.Next := null;
         end;
      else
         -- No program queued: execute an empty step (e.g. bare RUN in REPL).
         Execute (null);
      end if;
   end Run_Active_Program;

   procedure Add_Pending_Mod (Kind : Column_Mod_Kind; Name : String) is
      New_Mod : constant Column_Mod_List := new Column_Mod_Node;
      Last : Column_Mod_List := Pending_Mods;
      Upper : constant String := To_Upper (Name);
   begin
      New_Mod.Kind := Kind; New_Mod.Len := Upper'Length;
      New_Mod.Name (1 .. Upper'Length) := Upper; New_Mod.Next := null;
      if Pending_Mods = null then Pending_Mods := New_Mod;
      else
         while Last.Next /= null loop Last := Last.Next; end loop;
         Last.Next := New_Mod;
      end if;
   end Add_Pending_Mod;

   procedure Clear_Pending_Mods is
   begin
      while Pending_Mods /= null loop
         declare Tmp : constant Column_Mod_List := Pending_Mods;
         begin Pending_Mods := Pending_Mods.Next; -- Implicit free managed by GC or let it leak for now in Ada
         end;
      end loop;
   end Clear_Pending_Mods;

   procedure Apply_Pending_Mods is
      Keep_Mods_Exist : Boolean := False;
      Keep_List : Name_Sets.Set;
      Curr : Column_Mod_List := Pending_Mods;
   begin
      -- First, check for KEEP statements and build a keep list
      while Curr /= null loop
         if Curr.Kind = Mod_Keep then
            Keep_Mods_Exist := True;
            Keep_List.Include (Curr.Name(1 .. Curr.Len));
         end if;
         Curr := Curr.Next;
      end loop;

      -- If there was a KEEP statement, drop everything not in the list
      if Keep_Mods_Exist then
         declare
            All_Cols : String_List_Access := Get_Column_Names;
         begin
            if All_Cols /= null then
               for I in All_Cols'Range loop
                  declare
                     Col_Name : constant String := To_Upper(All_Cols(I).all);
                  begin
                     if not Keep_List.Contains(Col_Name) then
                        Drop_Column(Col_Name);
                     end if;
                  end;
               end loop;
               GNAT.Strings.Free(All_Cols);
            end if;
         end;
      end if;

      -- Now handle explicit drops
      Curr := Pending_Mods;
      while Curr /= null loop
         if Curr.Kind = Mod_Drop then
            Drop_Column (Curr.Name (1 .. Curr.Len));
         end if;
         Curr := Curr.Next;
      end loop;

      Clear_Pending_Mods;
   end Apply_Pending_Mods;

   procedure Expand_Range (Kind : Column_Mod_Kind; Range_Spec : Variable_Range) is
      Col_Names : constant String_List_Access := Get_Column_Names;
      Start_Name : constant String := (if Range_Spec.Start_Len in 1 .. 32 then To_Upper (Range_Spec.Start_Name (1 .. Range_Spec.Start_Len)) else "");
      End_Name   : constant String := (if Range_Spec.End_Len in 1 .. 32 then To_Upper (Range_Spec.End_Name (1 .. Range_Spec.End_Len)) else "");
      Start_Idx, End_Idx : Natural := 0;
   begin
      if not Range_Spec.Is_Range then
         Add_Pending_Mod (Kind, Start_Name);
      elsif Col_Names /= null then
         for I in Col_Names'Range loop
            if To_Upper (Col_Names (I).all) = Start_Name then Start_Idx := I; end if;
            if To_Upper (Col_Names (I).all) = End_Name then End_Idx := I; end if;
         end loop;
         if Start_Idx > 0 and End_Idx > 0 then
            if Start_Idx > End_Idx then
               declare T : constant Natural := Start_Idx; begin Start_Idx := End_Idx; End_Idx := T; end;
            end if;
            for I in Start_Idx .. End_Idx loop
               Add_Pending_Mod (Kind, Col_Names (I).all);
            end loop;
         end if;
         declare Old : String_List_Access := Col_Names; begin GNAT.Strings.Free (Old); end;
      end if;
   end Expand_Range;

   function Has_Output_Statement (Stmt : Statement_Access; Boundary : Statement_Access := null) return Boolean is
      Curr : Statement_Access := Stmt;
   begin
      while Curr /= null and then Curr /= Boundary loop
         if Curr.Kind = Stmt_WRITE then return True; end if;
         
         case Curr.Kind is
            when Stmt_IF =>
               if Has_Output_Statement (Curr.Then_Branch) or else
                  Has_Output_Statement (Curr.Else_Branch) then
                  return True;
               end if;
            when Stmt_FOR =>
               if Has_Output_Statement (Curr.For_Body) then return True; end if;
            when Stmt_WHILE =>
               if Has_Output_Statement (Curr.While_Body) then return True; end if;
            when Stmt_LOOP_REPEAT =>
               if Has_Output_Statement (Curr.Repeat_Body) then return True; end if;
            when Stmt_SELECT =>
               declare
                  Branch : Case_Branch := Curr.Branches;
               begin
                  while Branch /= null loop
                     if Has_Output_Statement (Branch.Branch_Body) then return True; end if;
                     Branch := Branch.Next;
                  end loop;
                  if Has_Output_Statement (Curr.Otherwise_Part) then return True; end if;
               end;
            when others => null;
         end case;
         Curr := Curr.Next;
      end loop;
      return False;
   end Has_Output_Statement;

   
   

   function Full_Path (Path : String; Category : String) return String is
      Cat  : constant String := To_Upper (Category);
      Base : Unbounded_String := Null_Unbounded_String;
      Result : Unbounded_String;

      function Has_Extension (S : String) return Boolean is
      begin
         for I in reverse S'Range loop
            if S (I) = '.' then
               return True;
            elsif S (I) = '/' or else S (I) = '\' then
               return False;
            end if;
         end loop;
         return False;
      end Has_Extension;
   begin
      -- 1. Handle absolute paths
      if Path'Length >= 1 and then (Path (Path'First) = '/' or else (Path'Length >= 2 and then Path (Path'First + 1) = ':')) then
         Result := To_Unbounded_String (Path);
      else
         -- 2. Handle FPATH prepending
         if Cat = "USE" then
            Base := SData.Config.FPath_Use;
         elsif Cat = "SAVE" then
            Base := SData.Config.FPath_Save;
         elsif Cat = "SUBMIT" then
            Base := SData.Config.FPath_Submit;
         elsif Cat = "OUTPUT" then
            Base := SData.Config.FPath_Output;
         end if;

         if Base /= Null_Unbounded_String and then To_String (Base) /= "" then
            declare
               B : constant String := To_String (Base);
            begin
               if B (B'Last) = '/' or else B (B'Last) = '\' then
                  Result := To_Unbounded_String (B & Path);
               else
                  Result := To_Unbounded_String (B & "/" & Path);
               end if;
            end;
         else
            Result := To_Unbounded_String (Path);
         end if;
      end if;

      -- 3. Append default extensions if missing
      declare
         S : constant String := To_String (Result);
      begin
         if To_Upper (S) = "MOCK" or else To_Upper (S) = "MOCK_DATA" then
            return S;
         end if;
         if not Has_Extension (S) then
            if Cat = "USE" or else Cat = "SAVE" then
               return S & ".CSV";
            elsif Cat = "SUBMIT" then
               return S & ".CMD";
            elsif Cat = "OUTPUT" then
               return S & ".DAT";
            end if;
         end if;
         return S;
      end;
   end Full_Path;

   procedure Execute_Statement (Stmt : Statement_Access) is
      procedure Print_Help (Topic : String := "") is
         T : constant String := To_Upper (Topic);
      begin
         if Stmt = null then return; end if;
         if T = "" then
            Put_Line ("SData version " & SData.Config.Version_Str);
            Put_Line ("Available Commands:");
            Put_Line ("  Data:        USE, SAVE, RUN, NEW, NAMES, WRITE, DELETE");
            Put_Line ("  Variables:   LET, SET, UNSET, HOLD, UNHOLD, KEEP, DROP, RENAME");
            Put_Line ("  Arrays:      ARRAY, DIM");
            Put_Line ("  Control:     IF, SELECT, FOR, WHILE, REPEAT");
            Put_Line ("  Data step:   BY, SORT, REPEAT");
            Put_Line ("  Output:      PRINT, OUTPUT, ECHO, DIGITS");
            Put_Line ("  Files/paths: FPATH");
            Put_Line ("  Session:     RSEED, SYSTEM, SUBMIT, HELP, OPTIONS, QUIT, END");
            New_Line;
            Put_Line ("Available Functions:");
            Put_Line ("  Math:        ABS, SQRT, LOG, LOG10, EXP, ROUND, CEIL, FLOOR, INT, MOD");
            Put_Line ("  Trig (rad):  SIN, COS, TAN, ATN, ATAN2, SINH, COSH, TANH");
            Put_Line ("  Trig (deg):  SIND, COSD, TAND, ATND, ATAN2D");
            Put_Line ("  String:      LEN, LEFT$, RIGHT$, MID$, TRIM$, UCASE$, LCASE$,");
            Put_Line ("               POS, CHR$, STR$, VAL, NUM$");
            Put_Line ("  Conversion:  NUM, HEX$, OCT$, BIN$");
            Put_Line ("  Record:      RECNO, BOF, EOF, BOG, EOG, LAG, LAGC$, OBS, OBSC$");
            Put_Line ("  Special:     MISSING, NMISS, RAN, RANDOM, DATE$, TIME$, SHELL");
            Put_Line ("  Aggregate:   SUM, MEAN, STD, VAR, MIN, MAX, MEDIAN, N, NMISS");
            Put_Line ("  Stat PDF:    ZDF, NDF, UDF, EDF, BDF, PDF, GDF, XDF, TDF, FDF,");
            Put_Line ("               MDF, WDF, LDF");
            Put_Line ("  Stat CDF:    ZCF, NCF, UCF, ECF, BCF, PCF, GCF, XCF, TCF, FCF,");
            Put_Line ("               MCF, WCF, LCF");
            Put_Line ("  Stat IDF:    ZIF, NIF, UIF, EIF, BIF, GIF, XIF, TIF, FIF, WIF,");
            Put_Line ("               LIF, PIF");
            Put_Line ("  Stat RN:     ZRN, NRN, URN, ERN, PRN, GRN, MRN, XRN, TRN,");
            Put_Line ("               FRN, WRN, LRN, RAN, RANDOM");
            New_Line;
            Put_Line ("Use HELP <name> for details.  Use HELP /ALL for the full reference.");
         elsif T = "USE" then
            Put_Line ("Command: USE [MOCK | ""filename""] [/FMT=format] [/NSCAN=n]");
            Put_Line ("Loads a dataset from CSV, ODF, or OOXML files into the Data Table.");
            Put_Line ("USE MOCK generates synthetic test data.");
            Put_Line ("Options:");
            Put_Line ("  /FMT=format  Specifies the file format (CSV, ODF, OOXML).");
            Put_Line ("               Default is auto-detected from file extension.");
            Put_Line ("  /NSCAN=n     Number of rows to scan for type detection (default: 20).");
         elsif T = "SAVE" then
            Put_Line ("Command: SAVE ""filename"" [/FMT=format] [/HEADER=YES|NO]");
            Put_Line ("Queues the current Data Table to be saved after the next RUN command.");
            Put_Line ("Options:");
            Put_Line ("  /FMT=format  Specifies the output format (CSV, ODF, OOXML).");
            Put_Line ("               Default is auto-detected from file extension.");
            Put_Line ("  /HEADER=val  Whether to write a header row (YES or NO). Default: YES.");
         elsif T = "WRITE" then
            Put_Line ("Command: WRITE");
            Put_Line ("Explicitly writes the current PDV record to the output table.");
            Put_Line ("Suppresses the automatic end-of-step write for that record.");
         elsif T = "SUBMIT" then
            Put_Line ("Command: SUBMIT ""filename""");
            Put_Line ("Executes commands from an external script file. Default extension: .CMD.");
            Put_Line ("Provides cycle detection to prevent recursive submission.");
         elsif T = "SYSTEM" then
            Put_Line ("Command: SYSTEM ""command""");
            Put_Line ("Executes an external shell command. Disabled by --noshell.");
            Put_Line ("Uses /bin/sh on POSIX systems to avoid profile script side-effects.");
         elsif T = "PRINT" then
            Put_Line ("Command: PRINT [expr [[,] | [;] expr] ...]");
            Put_Line ("Outputs values to the console, separated by spaces.");
            Put_Line ("No arguments: Prints all permanent variables for the current record.");
         elsif T = "RUN" then
            Put_Line ("Command: RUN");
            Put_Line ("Triggers the execution of the Data Step and any deferred SAVE operations.");
         elsif T = "LET" then
            Put_Line ("Command: LET variable = expression");
            Put_Line ("Creates a permanent column in the table or updates an existing one.");
         elsif T = "SET" then
            Put_Line ("Command: SET variable = expression");
            Put_Line ("Creates a temporary variable that persists only during the Data Step.");
         elsif T = "UNSET" then
            Put_Line ("Command: UNSET variable(s)");
            Put_Line ("Removes one or more session variables from memory.");
         elsif T = "ARRAY" then
            Put_Line ("Command: ARRAY array_name variable(s)");
            Put_Line ("Creates a virtual array providing indexed access to existing variables.");
         elsif T = "DIM" then
            Put_Line ("Command: DIM <arrayname> (<lower> [TO <upper>]) [/TEMP]");
            Put_Line ("Creates a permanent or temporary array (real variables).");
            Put_Line ("Elements are initialized to missing. /TEMP makes it temporary.");
            Put_Line ("A DIM statement that references an existing variable or array shall fail.");
         elsif T = "BY" then
            Put_Line ("Command: BY variable(s)");
            Put_Line ("Groups data by variables. Enables FIRST. and LAST. indicators.");
         elsif T = "SORT" then
            Put_Line ("Command: SORT variable(s)");
            Put_Line ("Reorders the Data Table based on the specified variables.");
         elsif T = "NEW" then
            Put_Line ("Command: NEW");
            Put_Line ("Clears the Data Table, all variables, and the queued program.");
         elsif T = "NAMES" then
            Put_Line ("Command: NAMES");
            Put_Line ("Lists currently defined permanent and temporary variables.");
         elsif T = "DELETE" then
            Put_Line ("Command: DELETE");
            Put_Line ("Discards the current record; processing moves to the next record.");
         elsif T = "HOLD" then
            Put_Line ("Command: HOLD [variable(s)]");
            Put_Line ("Retains the listed permanent variables across records.");
         elsif T = "UNHOLD" then
            Put_Line ("Command: UNHOLD [variable(s)]");
            Put_Line ("Cancels a previous HOLD. No args = unhold all.");
         elsif T = "KEEP" then
            Put_Line ("Command: KEEP variable(s)");
            Put_Line ("Drops all permanent variables NOT listed after the next RUN.");
         elsif T = "DROP" then
            Put_Line ("Command: DROP variable(s)");
            Put_Line ("Drops the listed permanent variables after the next RUN.");
         elsif T = "RENAME" then
            Put_Line ("Command: RENAME old=new [, old=new ...]");
            Put_Line ("Renames columns in the Data Table.");
         elsif T = "IF" or else T = "ELSEIF" then
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
         elsif T = "SELECT" then
            Put_Line ("Command: SELECT [expression]");
            Put_Line ("Multi-way branch using CASE (value) or WHEN (condition).");
            Put_Line ("Example:");
            Put_Line ("  SELECT GRADE$");
            Put_Line ("    CASE ""A"" : PRINT ""EXCELLENT""");
            Put_Line ("    CASE ""B"" : PRINT ""GOOD""");
            Put_Line ("    OTHERWISE : PRINT ""SEE ME""");
            Put_Line ("  END SELECT");
         elsif T = "FOR" then
            Put_Line ("Command: FOR var = start TO end [STEP s] ... NEXT");
            Put_Line ("Counter-controlled loop.");
            Put_Line ("Example:");
            Put_Line ("  FOR I = 1 TO 10 STEP 2");
            Put_Line ("    PRINT I");
            Put_Line ("  NEXT I");
         elsif T = "WHILE" then
            Put_Line ("Command: WHILE condition ... WEND");
            Put_Line ("Condition-controlled loop; executes while condition is true.");
            Put_Line ("Example:");
            Put_Line ("  SET I = 1");
            Put_Line ("  WHILE I <= 10");
            Put_Line ("    PRINT I");
            Put_Line ("    SET I = I + 1");
            Put_Line ("  WEND");
         elsif T = "REPEAT" then
            Put_Line ("Command (data step): REPEAT n  (creates n records)");
            Put_Line ("Command (loop):      REPEAT ... UNTIL condition");
            Put_Line ("Example:");
            Put_Line ("  SET I = 1");
            Put_Line ("  REPEAT");
            Put_Line ("    PRINT I");
            Put_Line ("    SET I = I + 1");
            Put_Line ("  UNTIL I > 10");
         elsif T = "OUTPUT" then
            Put_Line ("Command: OUTPUT [""filename""] [/CHARSET=...] [/FMT=...]");
            Put_Line ("Redirects all console output to a file (written to file AND stdout).");
            Put_Line ("No arguments: Closes the current output file.");
            Put_Line ("Options:");
            Put_Line ("  /CHARSET=cs  Specifies the character set (e.g., UTF-8, ASCII).");
            Put_Line ("  /FMT=format  Specifies the file format (e.g., CSV, ODF).");
         elsif T = "ECHO" then
            Put_Line ("Command: ECHO ON | OFF");
            Put_Line ("Enables or disables writing console output to stdout.");
         elsif T = "DIGITS" then
            Put_Line ("Command: DIGITS n");
            Put_Line ("Sets decimal places for floating-point output (default 5).");
         elsif T = "FPATH" then
            Put_Line ("Command: FPATH [path] [/ USE | SAVE | SUBMIT | OUTPUT]");
            Put_Line ("Sets the default directory for the specified command(s).");
         elsif T = "RSEED" then
            Put_Line ("Command: RSEED n");
            Put_Line ("Seeds the random number generator with integer n.");
         elsif T = "HELP" then
            Put_Line ("Command: HELP [topic | /ALL]");
            Put_Line ("Displays help. HELP /ALL prints the full reference.");
         elsif T = "QUIT" or else T = "END" then
            Put_Line ("Command: QUIT | END");
            Put_Line ("Exits the interpreter.");
         elsif T = "MEAN" then
            Put_Line ("Function: MEAN(v1, [v2, ...])");
            Put_Line ("Returns the row-wise mean of the specified values or arrays.");
         elsif T = "SUM" then
            Put_Line ("Function: SUM(v1, [v2, ...])");
            Put_Line ("Returns the row-wise sum of the specified values or arrays.");
         elsif T = "ABS" then
            Put_Line ("Function: ABS(x)");
            Put_Line ("Returns the absolute value of x.");
         elsif T = "SQRT" then
            Put_Line ("Function: SQRT(x)");
            Put_Line ("Returns the square root of x.");
         elsif T = "LOG" then
            Put_Line ("Function: LOG(x)");
            Put_Line ("Returns the natural logarithm of x.");
         elsif T = "LOG10" then
            Put_Line ("Function: LOG10(x)");
            Put_Line ("Returns the base-10 logarithm of x.");
         elsif T = "EXP" then
            Put_Line ("Function: EXP(x)");
            Put_Line ("Returns e raised to the power of x.");
         elsif T = "ROUND" then
            Put_Line ("Function: ROUND(x, [n])");
            Put_Line ("Rounds x to n decimal places (default: 0).");
         elsif T = "CEIL" then
            Put_Line ("Function: CEIL(x)");
            Put_Line ("Returns the smallest integer greater than or equal to x.");
         elsif T = "FLOOR" then
            Put_Line ("Function: FLOOR(x)");
            Put_Line ("Returns the largest integer less than or equal to x.");
         elsif T = "INT" then
            Put_Line ("Function: INT(x)");
            Put_Line ("Returns the integer part of x (truncation).");
         elsif T = "MOD" then
            Put_Line ("Function: MOD(x, y)");
            Put_Line ("Returns the remainder of x divided by y.");
         elsif T = "STD" then
            Put_Line ("Function: STD(v1, [v2, ...])");
            Put_Line ("Returns the row-wise standard deviation.");
         elsif T = "VAR" then
            Put_Line ("Function: VAR(v1, [v2, ...])");
            Put_Line ("Returns the row-wise variance.");
         elsif T = "N" then
            Put_Line ("Function: N(v1, [v2, ...])");
            Put_Line ("Returns the count of non-missing values in the current row.");
         elsif T = "NMISS" then
            Put_Line ("Function: NMISS(v1, [v2, ...])");
            Put_Line ("Returns the count of missing values in the current row.");
         elsif T = "MAX" then
            Put_Line ("Function: MAX(v1, [v2, ...])");
            Put_Line ("Returns the maximum value across the specified arguments.");
         elsif T = "MIN" then
            Put_Line ("Function: MIN(v1, [v2, ...])");
            Put_Line ("Returns the minimum value across the specified arguments.");
         elsif T = "HOLD" then
            Put_Line ("Command: HOLD [variable(s)]");
            Put_Line ("Retains values of variables across records in a Data Step.");
         elsif T = "UNHOLD" then
            Put_Line ("Command: UNHOLD [variable(s)]");
            Put_Line ("Resets variables to missing for each record (default behavior).");
         -- ── Math functions ───────────────────────────────────────────────
         elsif T = "ABS" then
            Put_Line ("Function: ABS(x)  ->  |x|");
         elsif T = "SQRT" then
            Put_Line ("Function: SQRT(x)  ->  square root of x (x >= 0)");
         elsif T = "LOG" then
            Put_Line ("Function: LOG(x)  ->  natural logarithm (x > 0)");
         elsif T = "LOG10" then
            Put_Line ("Function: LOG10(x)  ->  base-10 logarithm (x > 0)");
         elsif T = "EXP" then
            Put_Line ("Function: EXP(x)  ->  e raised to the power x");
         elsif T = "ROUND" then
            Put_Line ("Function: ROUND(x [, n])  ->  x rounded to n decimal places (default 0)");
         elsif T = "CEIL" then
            Put_Line ("Function: CEIL(x)  ->  smallest integer >= x");
         elsif T = "FLOOR" then
            Put_Line ("Function: FLOOR(x)  ->  largest integer <= x");
         elsif T = "INT" then
            Put_Line ("Function: INT(x)  ->  truncate toward zero");
         elsif T = "MOD" then
            Put_Line ("Function: MOD(x, y)  ->  x mod y (floor division remainder)");

         -- ── Trig (radians) ────────────────────────────────────────────────
         elsif T = "SIN" then  Put_Line ("Function: SIN(x)  ->  sine of x (radians)");
         elsif T = "COS" then  Put_Line ("Function: COS(x)  ->  cosine of x (radians)");
         elsif T = "TAN" then  Put_Line ("Function: TAN(x)  ->  tangent of x (radians)");
         elsif T = "ATN" then  Put_Line ("Function: ATN(x)  ->  arctangent of x (radians)");
         elsif T = "ATAN2" then Put_Line ("Function: ATAN2(y, x)  ->  arctangent of y/x (radians)");
         elsif T = "SINH" then Put_Line ("Function: SINH(x)  ->  hyperbolic sine");
         elsif T = "COSH" then Put_Line ("Function: COSH(x)  ->  hyperbolic cosine");
         elsif T = "TANH" then Put_Line ("Function: TANH(x)  ->  hyperbolic tangent");

         -- ── Trig (degrees) ────────────────────────────────────────────────
         elsif T = "SIND"  then Put_Line ("Function: SIND(x)   ->  sine of x (degrees)");
         elsif T = "COSD"  then Put_Line ("Function: COSD(x)   ->  cosine of x (degrees)");
         elsif T = "TAND"  then Put_Line ("Function: TAND(x)   ->  tangent of x (degrees)");
         elsif T = "ATND"  then Put_Line ("Function: ATND(x)   ->  arctangent of x (degrees)");
         elsif T = "ATAN2D" then Put_Line ("Function: ATAN2D(y,x) ->  arctangent of y/x (degrees)");

         -- ── String functions ─────────────────────────────────────────────
         elsif T = "LEN"   then Put_Line ("Function: LEN(s$)  ->  length of string s$");
         elsif T = "LEFT$" then Put_Line ("Function: LEFT$(s$, n)  ->  leftmost n characters");
         elsif T = "RIGHT$" then Put_Line ("Function: RIGHT$(s$, n)  ->  rightmost n characters");
         elsif T = "MID$"  then Put_Line ("Function: MID$(s$, start [, len])  ->  substring");
         elsif T = "TRIM$" then Put_Line ("Function: TRIM$(s$)  ->  strip leading/trailing spaces");
         elsif T = "UCASE$" then Put_Line ("Function: UCASE$(s$)  ->  convert to upper case");
         elsif T = "LCASE$" then Put_Line ("Function: LCASE$(s$)  ->  convert to lower case");
         elsif T = "POS"   then Put_Line ("Function: POS(needle$, haystack$)  ->  1-based position, 0=not found");
         elsif T = "CHR$"  then Put_Line ("Function: CHR$(n)  ->  character with ASCII code n");
         elsif T = "STR$"  then Put_Line ("Function: STR$(x)  ->  numeric x formatted as string");
         elsif T = "VAL"   then Put_Line ("Function: VAL(s$)  ->  parse string s$ as a number");
         elsif T = "NUM$"  then Put_Line ("Function: NUM$(x)  ->  numeric x formatted as string (alias for STR$)");
         elsif T = "NUM"   then Put_Line ("Function: NUM(x)  ->  convert string or integer x to float");

         -- ── Base conversion ───────────────────────────────────────────────
         elsif T = "HEX$" then Put_Line ("Function: HEX$(n)  ->  hexadecimal string for integer n");
         elsif T = "OCT$" then Put_Line ("Function: OCT$(n)  ->  octal string for integer n");
         elsif T = "BIN$" then Put_Line ("Function: BIN$(n)  ->  binary string for integer n");

         -- ── Record navigation ─────────────────────────────────────────────
         elsif T = "RECNO" then Put_Line ("Function: RECNO()  ->  current record number (1-based)");
         elsif T = "BOF"   then Put_Line ("Function: BOF()  ->  1 if first record, else 0");
         elsif T = "EOF"   then Put_Line ("Function: EOF()  ->  1 if last record, else 0");
         elsif T = "BOG"   then Put_Line ("Function: BOG()  ->  1 at start of BY group, else 0");
         elsif T = "EOG"   then Put_Line ("Function: EOG()  ->  1 at end of BY group, else 0");
         elsif T = "LAG" or else T = "LAGC$" then
            Put_Line ("Function: LAG(""varname"") / LAGC$(""varname"")");
            Put_Line ("  Returns the value of the named variable from the previous record.");
            Put_Line ("  Returns missing for the first record.");
         elsif T = "OBS" or else T = "OBSC$" then
            Put_Line ("Function: OBS(""varname"", row) / OBSC$(""varname"", row)");
            Put_Line ("  Returns the value of the named variable from the given row.");

         -- ── Special functions ─────────────────────────────────────────────
         elsif T = "MISSING" then Put_Line ("Function: MISSING(x)  ->  1 if x is missing, else 0");
         elsif T = "RAN" or else T = "RANDOM" then
            Put_Line ("Function: RAN() / RANDOM()  ->  uniform random number in [0, 1)");
            Put_Line ("  Use RSEED n before calling to get a reproducible sequence.");
         elsif T = "DATE$"  then Put_Line ("Function: DATE$()  ->  current date as ""YYYY-MM-DD""");
         elsif T = "TIME$"  then Put_Line ("Function: TIME$()  ->  current time as ""HH:MM:SS""");
         elsif T = "SHELL"  then
            Put_Line ("Function: SHELL(""command"")  ->  0 on success, 1 on failure");
            Put_Line ("  Disabled by --noshell flag.");

         -- ── Aggregate functions ────────────────────────────────────────────
         elsif T = "SUM"    then Put_Line ("Function: SUM(v1, ...)    ->  sum of non-missing values");
         elsif T = "MEAN"   then Put_Line ("Function: MEAN(v1, ...)   ->  mean of non-missing values");
         elsif T = "STD"    then Put_Line ("Function: STD(v1, ...)    ->  sample std dev");
         elsif T = "VAR"    then Put_Line ("Function: VAR(v1, ...)    ->  sample variance");
         elsif T = "MIN"    then Put_Line ("Function: MIN(v1, ...)    ->  minimum non-missing value");
         elsif T = "MAX"    then Put_Line ("Function: MAX(v1, ...)    ->  maximum non-missing value");
         elsif T = "MEDIAN" then Put_Line ("Function: MEDIAN(v1, ...) ->  median of non-missing values");
         elsif T = "N"      then Put_Line ("Function: N(v1, ...)      ->  count of non-missing values");

         -- ── Statistical distributions ─────────────────────────────────────
         --  Naming: Z=Normal, N=Normal(mu,sigma), U=Uniform, E=Exponential,
         --          B=Beta, P=Poisson, G=Gamma, X=Chi-square, T=Student-T,
         --          F=F, M=Binomial, W=Weibull, L=Laplace
         --  Suffix: DF=PDF, CF=CDF, IF=IDF(quantile), RN=random variate
         elsif T = "ZDF" or T = "ZCF" or T = "ZIF" or T = "ZRN" then
            Put_Line ("Standard Normal (mu=0, sigma=1): ZDF(x) ZCF(x) ZIF(p) ZRN()");
         elsif T = "NDF" or T = "NCF" or T = "NIF" or T = "NRN" then
            Put_Line ("Normal: NDF(x,mu,sigma) NCF(x,mu,sigma) NIF(p,mu,sigma) NRN(mu,sigma)");
         elsif T = "UDF" or T = "UCF" or T = "UIF" or T = "URN" then
            Put_Line ("Uniform: UDF(x,lo,hi) UCF(x,lo,hi) UIF(p,lo,hi) URN(lo,hi)");
         elsif T = "EDF" or T = "ECF" or T = "EIF" or T = "ERN" then
            Put_Line ("Exponential: EDF(x,rate) ECF(x,rate) EIF(p,rate) ERN(rate)");
         elsif T = "BDF" or T = "BCF" or T = "BIF" or T = "BRN" then
            Put_Line ("Beta: BDF(x,a,b) BCF(x,a,b) BIF(p,a,b)  [no BRN]");
         elsif T = "PDF" or T = "PCF" or T = "PIF" or T = "PRN" then
            Put_Line ("Poisson: PDF(k,lambda) PCF(k,lambda) PIF(p,lambda) PRN(lambda)");
         elsif T = "GDF" or T = "GCF" or T = "GIF" or T = "GRN" then
            Put_Line ("Gamma: GDF(x,shape,rate) GCF(x,shape,rate) GIF(p,shape,rate) GRN(shape,rate)");
         elsif T = "XDF" or T = "XCF" or T = "XIF" or T = "XRN" then
            Put_Line ("Chi-square: XDF(x,df) XCF(x,df) XIF(p,df) XRN(df)");
         elsif T = "TDF" or T = "TCF" or T = "TIF" or T = "TRN" then
            Put_Line ("Student-T: TDF(x,df) TCF(x,df) TIF(p,df) TRN(df)");
         elsif T = "FDF" or T = "FCF" or T = "FIF" or T = "FRN" then
            Put_Line ("F: FDF(x,df1,df2) FCF(x,df1,df2) FIF(p,df1,df2) FRN(df1,df2)");
         elsif T = "MDF" or T = "MCF" or T = "MIF" or T = "MRN" then
            Put_Line ("Binomial: MDF(k,n,p) MCF(k,n,p) MIF(p,n,prob)  [no MRN]");
         elsif T = "WDF" or T = "WCF" or T = "WIF" or T = "WRN" then
            Put_Line ("Weibull: WDF(x,scale,shape) WCF(x,scale,shape) WIF(p,scale,shape) WRN(scale,shape)");
         elsif T = "LDF" or T = "LCF" or T = "LIF" or T = "LRN" then
            Put_Line ("Laplace: LDF(x,loc,scale) LCF(x,loc,scale) LIF(p,loc,scale) LRN(loc,scale)");

         elsif T = "OPTIONS" then
            Put_Line ("Runtime Configuration Flags:");
            Put_Line ("  --noshell            : Disable SYSTEM/SHELL");
            Put_Line ("  --ignore-math-errors : Domain errors return MISSING");
            Put_Line ("  --clen <n>           : Set max character variable length");
            Put_Line ("  -m <n>               : Set max in-memory table rows");
            Put_Line ("  -k                   : Continue execution after statement error");

         -- ── HELP /ALL ────────────────────────────────────────────────────
         elsif T = "/ALL" then
            declare
               type Topic_Array is array (Positive range <>) of GNAT.Strings.String_Access;
               Cmds : constant Topic_Array := (
                  new String'("USE"), new String'("SAVE"), new String'("RUN"),
                  new String'("NEW"), new String'("NAMES"), new String'("WRITE"),
                  new String'("DELETE"), new String'("LET"), new String'("SET"), new String'("UNSET"),
                  new String'("HOLD"), new String'("UNHOLD"), new String'("KEEP"),
                  new String'("DROP"), new String'("RENAME"), new String'("ARRAY"),
                  new String'("DIM"), new String'("IF"), new String'("SELECT"),
                  new String'("FOR"), new String'("WHILE"), new String'("REPEAT"),
                  new String'("BY"), new String'("SORT"), new String'("PRINT"),
                  new String'("OUTPUT"), new String'("ECHO"), new String'("DIGITS"),
                  new String'("FPATH"), new String'("RSEED"), new String'("SYSTEM"),
                  new String'("SUBMIT"), new String'("HELP"), new String'("QUIT"), new String'("OPTIONS")
               );
               Funcs : constant Topic_Array := (
                  new String'("ABS"), new String'("SQRT"), new String'("LOG"),
                  new String'("LOG10"), new String'("EXP"), new String'("ROUND"),
                  new String'("CEIL"), new String'("FLOOR"), new String'("INT"),
                  new String'("MOD"), new String'("SIN"), new String'("COS"),
                  new String'("TAN"), new String'("ATN"), new String'("ATAN2"),
                  new String'("SINH"), new String'("COSH"), new String'("TANH"),
                  new String'("SIND"), new String'("COSD"), new String'("TAND"),
                  new String'("ATND"), new String'("ATAN2D"),
                  new String'("LEN"), new String'("LEFT$"), new String'("RIGHT$"),
                  new String'("MID$"), new String'("TRIM$"), new String'("UCASE$"),
                  new String'("LCASE$"), new String'("POS"), new String'("CHR$"),
                  new String'("STR$"), new String'("VAL"), new String'("NUM$"),
                  new String'("NUM"), new String'("HEX$"), new String'("OCT$"),
                  new String'("BIN$"), new String'("RECNO"), new String'("BOF"),
                  new String'("EOF"), new String'("BOG"), new String'("EOG"),
                  new String'("LAG"), new String'("OBS"), new String'("MISSING"),
                  new String'("NMISS"), new String'("RAN"), new String'("DATE$"),
                  new String'("TIME$"), new String'("SHELL"), new String'("SUM"),
                  new String'("MEAN"), new String'("STD"), new String'("VAR"),
                  new String'("MIN"), new String'("MAX"), new String'("MEDIAN"),
                  new String'("N"), new String'("ZDF"), new String'("NDF"),
                  new String'("UDF"), new String'("EDF"), new String'("BDF"),
                  new String'("PDF"), new String'("GDF"), new String'("XDF"),
                  new String'("TDF"), new String'("FDF"), new String'("MDF"),
                  new String'("WDF"), new String'("LDF"), new String'("ZIF"),
                  new String'("NIF"), new String'("UIF"), new String'("EIF"),
                  new String'("BIF"), new String'("GIF"), new String'("XIF"),
                  new String'("TIF"), new String'("FIF"), new String'("WIF"),
                  new String'("LIF"), new String'("PIF")
               );
            begin
               Put_Line ("=== COMMAND REFERENCE ===");
               for I in Cmds'Range loop
                  Print_Help (Cmds (I).all); New_Line;
               end loop;
               Put_Line ("=== FUNCTION REFERENCE ===");
               for I in Funcs'Range loop
                  Print_Help (Funcs (I).all); New_Line;
               end loop;
               for I in Cmds'Range  loop declare Old : GNAT.Strings.String_Access := Cmds (I);  begin GNAT.Strings.Free (Old); end; end loop;
               for I in Funcs'Range loop declare Old : GNAT.Strings.String_Access := Funcs (I); begin GNAT.Strings.Free (Old); end; end loop;
            end;

         else
            Put_Line ("Help topic not found: " & T);
            Put_Line ("Type HELP for a list of commands and functions.");
         end if;
      end Print_Help;

   begin
      if Stmt = null then return; end if;
      case Stmt.Kind is
            when Stmt_HELP =>
               Print_Help (Stmt.Var_Name (1 .. Stmt.Var_Len));
            when Stmt_RUN =>
               Run_Active_Program;
            when Stmt_QUIT | Stmt_END =>
               null; -- Handled by loop termination
            when Stmt_LET | Stmt_SET =>
               declare
                  Var_Name_Str : constant String := Stmt.Var_Name(1 .. Stmt.Var_Len);
                  Expected     : Value_Kind;
                  Result       : Value;  -- Initialised in body so exceptions are caught below
               begin
                  Result := Evaluate (Stmt.Expr);
                  if Stmt.Is_Array then
                     declare
                        Idx_Val : constant Value := Evaluate (Stmt.Arr_Idx);
                        Idx : Integer;
                     begin
                        if Idx_Val.Kind = Val_Integer then Idx := Idx_Val.Int_Val;
                        elsif Idx_Val.Kind = Val_Numeric then Idx := Integer (Float'Floor (Idx_Val.Num_Val));
                        else 
                           raise Program_Error with "Invalid array index";
                        end if;

                        Set_Array_Element (Var_Name_Str, Idx, Result);
                     end;
                  else
                     Expected := Get_Expected_Kind (Var_Name_Str);
                     
                     -- Check for existence and type if already permanent
                     declare
                        Existing_Kind : constant Value_Kind := Get_Type (Var_Name_Str);
                     begin
                        if Existing_Kind /= Val_Missing then
                           if Expected /= Result.Kind and not (Expected = Val_Numeric and Result.Kind = Val_Integer) then
                              raise SData.Table.Type_Mismatch_Error with "Cannot assign " & Result.Kind'Image & " to " & Expected'Image;
                           end if;
                           -- Double check actual kind for dynamic variables without suffixes
                           if Existing_Kind = Val_String and Result.Kind /= Val_String then
                              raise SData.Table.Type_Mismatch_Error with "Cannot assign numeric to string variable " & Var_Name_Str;
                           elsif Existing_Kind /= Val_String and Result.Kind = Val_String then
                              raise SData.Table.Type_Mismatch_Error with "Cannot assign string to numeric variable " & Var_Name_Str;
                           end if;
                        end if;
                     end;

                     if Result.Kind /= Val_Missing then
                        if Expected = Val_Integer and Result.Kind /= Val_Integer then
                           Result := (Kind => Val_Integer, Int_Val => Integer (Float'Truncation (Convert_To_Float(Result))));
                        elsif Expected = Val_Numeric and Result.Kind = Val_Integer then
                           -- Promote integer to float.
                           Result := (Kind => Val_Numeric, Num_Val => Float (Result.Int_Val));
                        elsif Expected /= Result.Kind and not (Expected = Val_Numeric and Result.Kind = Val_Integer) then
                           raise SData.Table.Type_Mismatch_Error with "Cannot assign " & Result.Kind'Image & " to " & Expected'Image;
                        end if;
                     end if;
                     
                     -- Enforce --clen limit on string values before storing.
                     if Result.Kind = Val_String and then
                        SData.Config.Max_String_Len > 0 and then
                        Length (Result.Str_Val) > SData.Config.Max_String_Len
                     then
                        Put_Line_Error ("Warning: String truncated to " &
                                  Integer'Image (SData.Config.Max_String_Len) &
                                  " characters.");
                        Result.Str_Val := To_Unbounded_String (Slice (Result.Str_Val, 1, SData.Config.Max_String_Len));
                     end if;

                     if Stmt.Kind = Stmt_LET then
                        Set_Permanent (Var_Name_Str, Result);
                     else
                        Set_Temporary (Var_Name_Str, Result);
                     end if;
                  end if;
               exception
                  when E : SData.Table.Type_Mismatch_Error =>
                     raise Script_Error with "Type mismatch for variable " & Var_Name_Str & ": " & Ada.Exceptions.Exception_Message (E);
                  when Script_Error =>
                     --  Script_Error from evaluator (e.g. div-by-zero, domain error):
                     --  re-raise to let the top-level handler print it.
                     raise;
                  when E : others =>
                     raise Script_Error with "Assignment failed for variable " & Var_Name_Str & ": " & Ada.Exceptions.Exception_Message (E);
               end;
            when Stmt_PRINT =>
               if Stmt.Print_Args = null then
                  declare
                     Col_Names : constant String_List_Access := Get_Column_Names;
                  begin
                     if Col_Names /= null then
                        for I in Col_Names'Range loop
                           declare
                              Name : constant String := To_Upper (Col_Names (I).all);
                              Val  : constant Value  := Get (Name);
                           begin
                              Put (Name & ": " & To_String_Formatted (Val) & "  ");
                           end;
                        end loop;
                        New_Line;
                        declare
                           Old_List : String_List_Access := Col_Names;
                        begin
                           GNAT.Strings.Free (Old_List);
                        end;
                     end if;
                  end;
               else
                  declare Current_Arg : Expression_List := Stmt.Print_Args;
                  begin
                     while Current_Arg /= null loop
                        if Current_Arg.Expr.Kind = Expr_Variable then
                           declare
                              VName : constant String := To_Upper (Current_Arg.Expr.Var_Name (1 .. Current_Arg.Expr.Var_Len));
                           begin
                              if Has_Array (VName) then
                                 declare
                                    Start_Idx, End_Idx : Integer;
                                 begin
                                    Get_Array_Bounds (VName, Start_Idx, End_Idx);
                                    for I in Start_Idx .. End_Idx loop
                                       Put (To_String_Formatted (Get_Array_Element (VName, I)));
                                       if I /= End_Idx then Put (" "); end if;
                                    end loop;
                                 end;
                              else
                                 Put (To_String_Formatted (Evaluate (Current_Arg.Expr)));
                              end if;
                           end;
                        else
                           Put (To_String_Formatted (Evaluate (Current_Arg.Expr)));
                        end if;
                        if Current_Arg.Next /= null then Put (" "); end if;
                        Current_Arg := Current_Arg.Next;
                     end loop;
                     New_Line;
                  end;
               end if;
            when Stmt_USE =>
               SData.Config.Repeat_Active := False;
               SData.Config.Repeat_Count := 0;
               declare 
                  File_Name : constant String := Stmt.File_Path (1 .. Stmt.File_Len);
                  Expanded : String (1 .. 1024);
                  Exp_Len  : Natural := 0;
               begin
                  if Stmt.Is_Mock then
                     Exp_Len := 4;
                     Expanded (1 .. 4) := "MOCK";
                  else
                     declare Full : constant String := Full_Path (File_Name, "USE"); begin
                        Exp_Len := Full'Length;
                        Expanded (1 .. Exp_Len) := Full;
                     end;
                  end if;
                  SData.File_IO.Open_Input (Expanded(1 .. Exp_Len), 
                    (if Stmt.Format_Specified then Stmt.Fmt_Override else SData.Config.Input_Format));
               end;
               Input_File_Columns.Clear;
               Refresh_PDV_Names;
               declare Col_Names : GNAT.Strings.String_List_Access := Get_Column_Names;
               begin
                  if Col_Names /= null then
                     for I in Col_Names'Range loop Input_File_Columns.Include (To_Upper (Col_Names (I).all)); end loop;
                     GNAT.Strings.Free (Col_Names);
                  end if;
               end;
               if not SData.Config.Quiet_Mode and then Stmt.File_Path(1 .. Stmt.File_Len) /= "MOCK_DATA" 
                 and then Stmt.File_Path(1 .. Stmt.File_Len) /= "MOCK" then
                  --  Open_Input already prints success for some formats.
                  null;
               end if;
            when Stmt_SORT =>
               declare
                  Curr_Var : Variable_List := Stmt.Sort_Vars;
                  -- Count vars
                  Count : Natural := 0;
                  Tmp : Variable_List := Curr_Var;
               begin
                  while Tmp /= null loop Count := Count + 1; Tmp := Tmp.Next; end loop;
                  if Count > 0 then
                     declare
                        Crit : Sort_Criteria_Array (1 .. Count);
                        Idx : Positive := 1;
                     begin
                        while Curr_Var /= null loop
                           Crit (Idx).Name := (others => ' ');
                           Crit (Idx).Name (1 .. Curr_Var.Var.Start_Len) := To_Upper (Curr_Var.Var.Start_Name (1 .. Curr_Var.Var.Start_Len));
                           Crit (Idx).Len := Curr_Var.Var.Start_Len;
                           Crit (Idx).Dir := Ascending; -- For now, all ascending.
                           Idx := Idx + 1; Curr_Var := Curr_Var.Next;
                        end loop;
                        Sort (Crit);
                     end;
                  end if;
               end;
            when Stmt_BY =>
               Current_By_Vars.Clear;
               declare
                  Curr_Var : Variable_List := Stmt.Sort_Vars;
                  -- Count vars
                  Count : Natural := 0;
                  Tmp : Variable_List := Curr_Var;
               begin
                  while Tmp /= null loop Count := Count + 1; Tmp := Tmp.Next; end loop;
                  if Count > 0 then
                     declare
                        Crit : Sort_Criteria_Array (1 .. Count);
                        Idx : Positive := 1;
                     begin
                        while Curr_Var /= null loop
                           Crit (Idx).Name := (others => ' ');
                           Crit (Idx).Name (1 .. Curr_Var.Var.Start_Len) := To_Upper (Curr_Var.Var.Start_Name (1 .. Curr_Var.Var.Start_Len));
                           Crit (Idx).Len := Curr_Var.Var.Start_Len;
                           Crit (Idx).Dir := Ascending;
                           Current_By_Vars.Append (To_Unbounded_String (To_Upper (Curr_Var.Var.Start_Name (1 .. Curr_Var.Var.Start_Len))));
                           Idx := Idx + 1; Curr_Var := Curr_Var.Next;
                        end loop;
                        Sort (Crit);
                     end;
                  end if;
               end;
            when Stmt_REPEAT =>
               SData.Table.Clear; -- REPEAT cancels USE by clearing the table.
               SData.Config.Repeat_Active := True;
               SData.Config.Repeat_Count := Stmt.Count;
               Input_File_Columns.Clear;
            when Stmt_SAVE =>
               declare
                  File_Name : constant String := Stmt.File_Path (1 .. Stmt.File_Len);
                  Full      : constant String := Full_Path (File_Name, "SAVE");
               begin
                  SData.Config.Save_File_Path (1 .. Full'Length) := Full;
                  SData.Config.Save_File_Len := Full'Length;
                  SData.Config.Save_File_Fmt := (if Stmt.Format_Specified then Stmt.Fmt_Override else SData.Config.Output_Format);
                  SData.Config.Save_File_Active := True;
               end;
            when Stmt_KEEP | Stmt_DROP | Stmt_HOLD | Stmt_UNHOLD | Stmt_UNSET =>
               declare
                  Curr_Var : Variable_List := Stmt.Vars;
               begin
                  if Stmt.Kind = Stmt_UNSET then
                     while Curr_Var /= null loop
                        SData.Variables.Unset (To_Upper (Curr_Var.Var.Start_Name (1 .. Curr_Var.Var.Start_Len)));
                        Curr_Var := Curr_Var.Next;
                     end loop;
                  elsif Stmt.Kind = Stmt_KEEP or Stmt.Kind = Stmt_DROP then
                     declare K : constant Column_Mod_Kind := (if Stmt.Kind = Stmt_KEEP then Mod_Keep else Mod_Drop);
                     begin
                        while Curr_Var /= null loop
                           Expand_Range (K, Curr_Var.Var);
                           Curr_Var := Curr_Var.Next;
                        end loop;
                     end;
                  else
                     declare
                        State : constant Boolean := (Stmt.Kind = Stmt_HOLD);
                        procedure Set_Hold_For_Range (Range_Spec : Variable_Range) is
                           Col_Names : constant GNAT.Strings.String_List_Access := Get_Column_Names;
                           Start_Name : constant String := (if Range_Spec.Start_Len in 1 .. 32 then To_Upper (Range_Spec.Start_Name (1 .. Range_Spec.Start_Len)) else "");
                           End_Name   : constant String := (if Range_Spec.End_Len in 1 .. 32 then To_Upper (Range_Spec.End_Name (1 .. Range_Spec.End_Len)) else "");
                           Start_Idx, End_Idx : Natural := 0;
                        begin
                           if not Range_Spec.Is_Range then
                              Set_Hold (Start_Name, State);
                           elsif Col_Names /= null then
                              for I in Col_Names'Range loop
                                 if To_Upper (Col_Names (I).all) = Start_Name then Start_Idx := I; end if;
                                 if To_Upper (Col_Names (I).all) = End_Name then End_Idx := I; end if;
                              end loop;
                              if Start_Idx > 0 and End_Idx > 0 then
                                 if Start_Idx > End_Idx then
                                    declare T : constant Natural := Start_Idx; begin Start_Idx := End_Idx; End_Idx := T; end;
                                 end if;
                                 for I in Start_Idx .. End_Idx loop
                                    Set_Hold (Col_Names (I).all, State);
                                 end loop;
                              end if;
                              declare Old : String_List_Access := Col_Names; begin GNAT.Strings.Free (Old); end;
                           end if;
                        end Set_Hold_For_Range;
                     begin
                        if Curr_Var = null then
                           -- No arguments: HOLD all currently defined columns
                           declare
                              Col_Names : constant String_List_Access := Get_Column_Names;
                           begin
                              if Col_Names /= null then
                                 for I in Col_Names'Range loop
                                    Set_Hold (Col_Names (I).all, State);
                                 end loop;
                                 declare Old : String_List_Access := Col_Names; begin GNAT.Strings.Free (Old); end;
                              end if;
                           end;
                        else
                           while Curr_Var /= null loop
                              Set_Hold_For_Range (Curr_Var.Var);
                              Curr_Var := Curr_Var.Next;
                           end loop;
                        end if;
                     end;
                  end if;
               end;
            when Stmt_RENAME =>
               declare Curr : Rename_List := Stmt.Rename_Pairs;
               begin
                  while Curr /= null loop
                     Rename_Column (Curr.Old_Name (1 .. Curr.Old_Len), Curr.New_Name (1 .. Curr.New_Len));
                     Curr := Curr.Next;
                  end loop;
               end;
            when Stmt_ARRAY | Stmt_DIM =>
               declare
                  S : constant Statement_Access := Stmt;
               begin
                  if S.Kind = Stmt_ARRAY then
                     declare
                        V : Name_Vectors.Vector;
                        Curr_Var : Variable_List := S.Arr_Vars;

                        procedure Resolve_Range (Range_Spec : Variable_Range) is
                           Col_Names : constant GNAT.Strings.String_List_Access := Get_Column_Names;
                           Start_Name : constant String := (if Range_Spec.Start_Len in 1 .. 32 then To_Upper (Range_Spec.Start_Name (1 .. Range_Spec.Start_Len)) else "");
                           End_Name   : constant String := (if Range_Spec.End_Len in 1 .. 32 then To_Upper (Range_Spec.End_Name (1 .. Range_Spec.End_Len)) else "");
                           Start_Idx, End_Idx : Natural := 0;
                        begin
                           if not Range_Spec.Is_Range then
                              V.Append (To_Unbounded_String (Start_Name));
                           elsif Col_Names /= null then
                              for I in Col_Names'Range loop
                                 if To_Upper (Col_Names (I).all) = Start_Name then Start_Idx := I; end if;
                                 if To_Upper (Col_Names (I).all) = End_Name then End_Idx := I; end if;
                              end loop;
                              if Start_Idx > 0 and End_Idx > 0 then
                                 if Start_Idx > End_Idx then
                                    declare T : constant Natural := Start_Idx; begin Start_Idx := End_Idx; End_Idx := T; end;
                                 end if;
                                 for I in Start_Idx .. End_Idx loop
                                    V.Append (To_Unbounded_String (Col_Names (I).all));
                                 end loop;
                              end if;
                              declare Old : String_List_Access := Col_Names; begin GNAT.Strings.Free (Old); end;
                           end if;
                        end Resolve_Range;
                     begin
                        while Curr_Var /= null loop
                           Resolve_Range (Curr_Var.Var);
                           Curr_Var := Curr_Var.Next;
                        end loop;
                        Define_Array (S.Arr_Name (1 .. S.Arr_Name_Len), V);
                     end;
                  else -- Stmt_DIM
                     Dim_Array (S.Arr_Name (1 .. S.Arr_Name_Len), S.Arr_Start_Idx, S.Arr_End_Idx, S.Is_Temporary_Dim);
                  end if;
               exception
                  when E : others =>
                     raise Script_Error with "Error defining array " & S.Arr_Name (1 .. S.Arr_Name_Len) & ": " & Ada.Exceptions.Exception_Message (E);
               end;
            when Stmt_NAMES =>
               declare
                  T_Names : constant String_List_Access := Get_Column_Names;
                  S_Names : constant String_List_Access := Get_Session_Names;
               begin
                  Put_Line ("Permanent Variables (Table Columns):");
                  if T_Names /= null and then T_Names'Length > 0 then
                     for I in T_Names'Range loop
                        Put (T_Names (I).all & " ");
                     end loop;
                     New_Line;
                  else
                     Put_Line ("(none)");
                  end if;

                  Put_Line ("Session Variables (SET):");
                  if S_Names /= null and then S_Names'Length > 0 then
                     for I in S_Names'Range loop
                        Put (S_Names (I).all & " ");
                     end loop;
                     New_Line;
                  else
                     Put_Line ("(none)");
                  end if;

                  if T_Names /= null then
                     declare Old : String_List_Access := T_Names; begin GNAT.Strings.Free (Old); end;
                  end if;
                  if S_Names /= null then
                     declare Old : String_List_Access := S_Names; begin GNAT.Strings.Free (Old); end;
                  end if;
               end;
            when Stmt_SUBMIT =>
               declare
                  Final : constant String :=
                     Full_Path (Stmt.File_Path (1 .. Stmt.File_Len), "SUBMIT");
               begin
                  if Submit_Chain.Contains (Final) then
                     raise Script_Error with
                        "Recursive SUBMIT detected: " & Final;
                  end if;
                  Submit_Chain.Insert (Final);
                  declare
                     File   : Ada.Streams.Stream_IO.File_Type;
                     Stream : Ada.Streams.Stream_IO.Stream_Access;
                  begin
                     Ada.Streams.Stream_IO.Open
                        (File, Ada.Streams.Stream_IO.In_File, Final);
                     Stream := Ada.Streams.Stream_IO.Stream (File);
                        declare
                           Contents : String
                              (1 .. Integer (Ada.Streams.Stream_IO.Size (File)));
                        begin
                           String'Read (Stream, Contents);
                           Ada.Streams.Stream_IO.Close (File);
                           declare
                              Sub_Ctx  : Parser_Context;
                              Sub_Prog : Statement_Access;
                           begin
                              Initialize (Sub_Ctx, Contents);
                              Sub_Prog := Parse_Program (Sub_Ctx);
                              Execute (Sub_Prog);
                           end;
                        end;
                     exception
                        when Ada.Streams.Stream_IO.Name_Error =>
                           Submit_Chain.Delete (Final);
                           raise Script_Error with "SUBMIT: file not found: " & Final;
                        when others =>
                           Submit_Chain.Delete (Final);
                           raise;
                     end;
                     Submit_Chain.Delete (Final);
                  end;
            when Stmt_SYSTEM =>
               if SData.Config.Disable_Shell then
                  Put_Line_Error ("Error: SYSTEM command is disabled.");
               else
                  declare
                     Success : Boolean;
                  begin
                     SData.System.Shell_Execute (Stmt.File_Path(1 .. Stmt.File_Len), Success);
                  end;
               end if;
            when Stmt_SELECT =>
               declare
                  Val : constant Value := (if Stmt.Selector /= null then Evaluate (Stmt.Selector) else (Kind => Val_Missing));
                  Branch : Case_Branch := Stmt.Branches;
                  Matched : Boolean := False;
               begin
                  while Branch /= null loop
                     if Stmt.Selector = null then
                        -- CASE (condition) - execute first matched condition
                        declare Cond : Expression_List := Branch.Conditions;
                        begin
                           while Cond /= null loop
                              if Is_True (Evaluate (Cond.Expr)) then
                                 Execute_List (Branch.Branch_Body); Matched := True; exit;
                              end if;
                              Cond := Cond.Next;
                           end loop;
                        end;
                     else
                        -- SELECT (val) CASE (v1, v2)
                        declare Cond : Expression_List := Branch.Conditions;
                        begin
                           while Cond /= null loop
                              if Evaluate (Cond.Expr) = Val then
                                 Execute_List (Branch.Branch_Body); Matched := True; exit;
                              end if;
                              Cond := Cond.Next;
                           end loop;
                        end;
                     end if;
                     exit when Matched;
                     Branch := Branch.Next;
                  end loop;
                  if not Matched and then Stmt.Otherwise_Part /= null then
                     Execute_List (Stmt.Otherwise_Part);
                  end if;
               end;
            when Stmt_DELETE =>
               Current_Record_Deleted := True;
            when Stmt_WRITE =>
               SData.Variables.Flush_PDV_To_Output;
               SData.Table.Set_Record_Explicitly_Written (True);
            when Stmt_OUTPUT =>
               if SData.IO.Is_Redirected then
                  SData.IO.Close_Output;
               end if;

               if Stmt.File_Len > 0 then
                  declare
                     Final_Path : constant String := Full_Path (Stmt.File_Path (1 .. Stmt.File_Len), "OUTPUT");
                  begin
                     SData.IO.Open_Output (Final_Path);
                  exception
                     when others =>
                        SData.IO.Put_Line_Error ("Error: Could not create output file " & Final_Path);
                  end;
               end if;
            when Stmt_ECHO =>
               SData.IO.Set_Local_Echo (Stmt.Echo_State);
            when Stmt_IF =>
               if Is_True (Evaluate (Stmt.Condition)) then Execute_List (Stmt.Then_Branch);
               elsif Stmt.Else_Branch /= null then Execute_List (Stmt.Else_Branch); end if;
            when Stmt_WHILE =>
               while Is_True (Evaluate (Stmt.While_Cond)) loop Execute_List (Stmt.While_Body); end loop;
            when Stmt_FOR =>
               declare Start_Val : constant Value := Evaluate (Stmt.For_Start);
                       End_Val   : constant Value := Evaluate (Stmt.For_End);
                       Step_Val  : Value := (Kind => Val_Numeric, Num_Val => 1.0);
                       Current_I : Float;
               begin
                  if Stmt.For_Step /= null then Step_Val := Evaluate (Stmt.For_Step); end if;
                  begin
                     declare
                        S : constant Float := Convert_To_Float (Start_Val);
                        E : constant Float := Convert_To_Float (End_Val);
                        ST : constant Float := Convert_To_Float (Step_Val);
                     begin
                        Current_I := S;
                        while (ST > 0.0 and then Current_I <= E) or else (ST < 0.0 and then Current_I >= E) loop
                           Set_Permanent (Stmt.For_Var (1 .. Stmt.For_Var_Len), (Kind => Val_Numeric, Num_Val => Current_I));
                           Execute_List (Stmt.For_Body);
                           Current_I := Current_I + ST;
                        end loop;
                     end;
                  end;
               end;
            when Stmt_LOOP_REPEAT =>
               loop
                  Execute_List (Stmt.Repeat_Body);
                  exit when Is_True (Evaluate (Stmt.Until_Cond));
               end loop;
            when Stmt_DIGITS =>
               SData.Config.Print_Digits := Stmt.Digits_Count;
            when Stmt_FPATH =>
               declare
                  Path : constant String := (if Stmt.File_Len > 0 then Stmt.File_Path (1 .. Stmt.File_Len) else "");
                  Reset_All : constant Boolean := not (Stmt.Use_Flag or Stmt.Save_Flag or Stmt.Submit_Flag or Stmt.Output_Flag);
               begin
                  if Reset_All or Stmt.Use_Flag then 
                     SData.Config.FPath_Use := To_Unbounded_String (Path); 
                  end if;
                  if Reset_All or Stmt.Save_Flag then 
                     SData.Config.FPath_Save := To_Unbounded_String (Path); 
                  end if;
                  if Reset_All or Stmt.Submit_Flag then 
                     SData.Config.FPath_Submit := To_Unbounded_String (Path); 
                  end if;
                  if Reset_All or Stmt.Output_Flag then 
                     SData.Config.FPath_Output := To_Unbounded_String (Path); 
                  end if;
               end;
            when Stmt_RSEED =>
               declare
                  V : constant Value := Evaluate (Stmt.Seed_Expr);
                  S : constant Integer :=
                     (if V.Kind = Val_Integer then V.Int_Val
                      else Integer (Convert_To_Float (V)));
               begin
                  SData.Statistics.Set_Seed (S);
               end;
            when Stmt_NEW =>
               SData.Table.Clear;
               SData.Variables.Clear_Temporary;
               SData.Variables.Initialize_PDV;
               Clear_Active_Program;
               SData.Config.Repeat_Active := False;
               SData.Config.Repeat_Count := 0;
               SData.Config.Save_File_Active := False;
            pragma Warnings (Off, "choice is redundant");
            when others => null;  -- REPEAT, LOOP_REPEAT handled at the Execute level.
            pragma Warnings (On, "choice is redundant");
      end case;
   end Execute_Statement;

   procedure Execute_List (List : Statement_Access; Boundary : Statement_Access := null) is
      Curr : Statement_Access := List;
   begin
      if List = null then return; end if;
      while Curr /= null and then Curr /= Boundary loop
         Execute_Statement (Curr);
         exit when Current_Record_Deleted;
         Curr := Curr.Next;
      end loop;
   end Execute_List;

   procedure Execute (Prog : Statement_Access) is
      Step_Start : Statement_Access := Prog;
      Current    : Statement_Access;
      Num_Records : Natural;

      procedure Run_One_Step (Start, Boundary : Statement_Access) is
         Iter : Statement_Access;
         Global_Has_Write : constant Boolean := Has_Output_Statement (Start, Boundary);

         function Is_First_In_Group (Idx : Positive) return Boolean is
            Prev_Value : Value;
            Curr_Value : Value;
         begin
            if Idx = 1 then return True; end if;
            if Current_By_Vars.Is_Empty then return False; end if;
            for V of Current_By_Vars loop
               Prev_Value := Get_Value (Idx - 1, To_String(V));
               Curr_Value := Get_Value (Idx, To_String(V));
               if not (Curr_Value = Prev_Value) then 
                  return True; 
               end if;
            end loop;
            return False;
         end Is_First_In_Group;

         function Is_Last_In_Group (Idx : Positive) return Boolean is
            Curr_Value : Value;
            Next_Value : Value;
         begin
            if Idx = Num_Records then return True; end if;
            if Current_By_Vars.Is_Empty then return False; end if;
            for V of Current_By_Vars loop
               Curr_Value := Get_Value (Idx, To_String(V));
               Next_Value := Get_Value (Idx + 1, To_String(V));
               if not (Curr_Value = Next_Value) then 
                  return True; 
               end if;
            end loop;
            return False;
         end Is_Last_In_Group;

      begin
         Initialize_PDV;
         SData.Table.Initialize_Output_Table;

         if SData.Config.Repeat_Active then
            Num_Records := SData.Config.Repeat_Count;
         else
            Num_Records := (if Row_Count > 0 then Row_Count else 1);
         end if;

         for I in 1 .. Num_Records loop
            Set_Current_Record_Index (I);

            -- Step 1: Initialize PDV for this record
            Reset_PDV_Non_Held;
            Load_PDV_From_Table (I);

            -- Set First. and Last. indicators
            if not Current_By_Vars.Is_Empty then
               declare
                  BOG_Val : constant Boolean := Is_First_In_Group (I);
                  EOG_Val : constant Boolean := Is_Last_In_Group (I);
               begin
                  Set_BOG (BOG_Val);
                  Set_EOG (EOG_Val);
                  for V of Current_By_Vars loop
                     declare
                        Name : constant String := To_String (V);
                     begin
                        Set_Temporary ("FIRST." & Name, (Kind => Val_Integer, Int_Val => (if BOG_Val then 1 else 0)));
                        Set_Temporary ("LAST." & Name, (Kind => Val_Integer, Int_Val => (if EOG_Val then 1 else 0)));
                     end;
                  end loop;
               end;
            else
               Set_BOG (I = 1);
               Set_EOG (I = Num_Records);
            end if;

            Iter := Start;
            Current_Record_Deleted := False;
            SData.Table.Set_Record_Explicitly_Written (False);

            if Iter = null and then Boundary = null then
               -- Empty RUN: no statements to execute, but still snapshot the current PDV
               null;
            else
               while Iter /= null and then Iter /= Boundary loop
                  case Iter.Kind is
                     when Stmt_LET | Stmt_SET | Stmt_PRINT | Stmt_NAMES | Stmt_IF | Stmt_WHILE | Stmt_FOR | Stmt_LOOP_REPEAT | Stmt_SELECT | Stmt_DELETE | Stmt_WRITE | Stmt_OUTPUT | Stmt_ECHO | Stmt_HOLD | Stmt_UNHOLD | Stmt_ARRAY | Stmt_DIM | Stmt_SORT | Stmt_BY | Stmt_DIGITS | Stmt_HELP =>
                        begin
                           Execute_Statement(Iter);
                        exception
                           when E : Script_Error =>
                              if SData.Config.Continue_On_Error then
                                 Put_Line_Error ("Error: " & Ada.Exceptions.Exception_Message (E));
                              else
                                 raise;
                              end if;
                           when E : others =>
                              if SData.Config.Continue_On_Error then
                                 Put_Line_Error ("Error: " & Ada.Exceptions.Exception_Message (E));
                              else
                                 raise Script_Error with Ada.Exceptions.Exception_Message (E);
                              end if;
                        end;
                     when others => null;
                  end case;
                  exit when Current_Record_Deleted;
                  Iter := Iter.Next;
               end loop;
            end if;
            
            if not Current_Record_Deleted and then not Global_Has_Write then
               SData.Variables.Flush_PDV_To_Output;
            end if;
         end loop;
         
         SData.Table.Commit_Output_Table;
         Set_Current_Record_Index (0);
         Apply_Pending_Mods;
         if SData.Config.Save_File_Active then
            SData.File_IO.Open_Output (Full_Path (SData.Config.Save_File_Path (1 .. SData.Config.Save_File_Len), "SAVE"), SData.Config.Save_File_Fmt);
            if not SData.Config.Quiet_Mode then Put_Line ("Dataset saved: " & SData.Config.Save_File_Path (1 .. SData.Config.Save_File_Len)); end if;
            SData.Config.Save_File_Active := False;
         end if;
      end Run_One_Step;

   begin
      if Prog = null then
         Run_One_Step (null, null);
         return;
      end if;

      Current := Prog;
      while Current /= null loop
         if Current.Kind = Stmt_RUN then
            Run_One_Step (Step_Start, Current);
            declare
               RC  : constant String := Natural'Image (SData.Table.Row_Count);
               VC  : constant String := Natural'Image (SData.Table.Column_Count);
            begin
               Put_Line ("RUN complete. " &
                         RC (RC'First + 1 .. RC'Last) & " records and " &
                         VC (VC'First + 1 .. VC'Last) & " variables processed.");
            end;
            Step_Start := Current.Next;
         elsif Current.Kind /= Stmt_RUN and then Current.Kind /= Stmt_LET and then Current.Kind /= Stmt_SET and then Current.Kind /= Stmt_PRINT and then Current.Kind /= Stmt_IF and then Current.Kind /= Stmt_FOR and then Current.Kind /= Stmt_WHILE and then Current.Kind /= Stmt_LOOP_REPEAT and then Current.Kind /= Stmt_SELECT and then Current.Kind /= Stmt_DELETE and then Current.Kind /= Stmt_WRITE then
            begin
               Execute_Statement (Current);
            exception
               when E : Script_Error =>
                  if SData.Config.Continue_On_Error then
                     Put_Line_Error ("Error: " & Ada.Exceptions.Exception_Message (E));
                  else
                     raise;
                  end if;
               when E : others =>
                  if SData.Config.Continue_On_Error then
                     Put_Line_Error ("Error: " & Ada.Exceptions.Exception_Message (E));
                  else
                     raise Script_Error with Ada.Exceptions.Exception_Message (E);
                  end if;
            end;
         end if;
         Current := Current.Next;
      end loop;
   end Execute;

end SData.Interpreter;
