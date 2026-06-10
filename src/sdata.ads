--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

with SData_Core;

package SData is
   Script_Error : exception;

   --  Capacity limits — name/path/string constraints shared across the
   --  interpreter.  Both crates operate on the same data layer and MUST agree
   --  on these limits, so SData_Core (the shared library) is the single
   --  authoritative source.  The declarations below are thin re-exports: every
   --  existing SData.* / bare reference keeps working, but there is now exactly
   --  one literal per limit (in sdata_core.ads), so the two cannot silently
   --  diverge.  They remain static named numbers, so String(1..N) bounds and
   --  range checks are unaffected.
   Max_Name_Len        : constant := SData_Core.Max_Name_Len;
   Max_Path_Len        : constant := SData_Core.Max_Path_Len;
   Max_Sheet_Name_Len  : constant := SData_Core.Max_Sheet_Name_Len;
   Max_Delimiter_Len   : constant := SData_Core.Max_Delimiter_Len;
   Max_Charset_Len     : constant := SData_Core.Max_Charset_Len;
   Max_Options_Val_Len : constant := SData_Core.Max_Options_Val_Len;

end SData;
