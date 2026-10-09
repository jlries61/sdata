--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

separate (SData_Main)
--  Displays available command-line options.
procedure Print_Usage is
begin
   Put_Line ("Usage: sdata [options] [filename]");
   Put_Line ("Options:");
   Put_Line ("  -h, --help    Show this help message");
   Put_Line ("  -v, --version Show version information");
   Put_Line ("  --copyright   Show copyright and license information");
   Put_Line ("  -m <cells>    Set max in-memory table cells (rows*cols; 0 = unlimited)");
   Put_Line ("  -t <count>    Set max temporary variables");
   Put_Line ("  --clen <len>  Set max character variable length (default 256)");
   Put_Line ("  --shell-timeout=N        SYSTEM/SHELL timeout in seconds (0=unlimited; default 300 in batch)");
   Put_Line ("  --noshell                Disable SHELL command and function");
   Put_Line ("  --nosubmit               Disable SUBMIT command");
   Put_Line ("  -k, --continue-on-error  Continue executing after a statement error");
   Put_Line ("  --ignore-math-errors     Math domain errors return MISSING instead of halting");
   Put_Line ("  --progress               Report record-count progress on stderr for long USE/RUN/SORT runs");
   Put_Line ("  -u, --infmt              Input dataset and format");
   Put_Line ("  -s, --outfmt             Output dataset and format");
   Put_Line ("  -o <file>                Console output file");
   Put_Line ("  -q                       Suppress console output (Quiet Mode)");
   Put_Line ("  -p <pager>               External pager command for interactive output");
   Put_Line ("                           (e.g. ""less -F"", ""more""); ignored in batch mode;");
   Put_Line ("                           incompatible with --noshell");
   Put_Line ("  --debug[=N]              Trace execution to stderr");
   Put_Line ("                           1=I/O only  2=+record/flow  3=+assignments (default 3)");
end Print_Usage;
