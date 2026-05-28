--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

--  SData.Transient_Table — an in-memory table value type used by sdata's
--  merge orchestration to hold per-input intermediates. Independent of
--  SData_Core.Table (which is a singleton). Operations on a transient
--  table do not touch the global SData_Core.Table state.

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with SData_Core.Table;
with SData_Core.Values;

package SData.Transient_Table is

   type Table is tagged private;
   --  NOTE: NOT limited — must be copyable for heap-allocated storage in
   --  Execute_USE's Snapshot vector.

   --  Schema
   procedure Add_Column
     (T        : in out Table;
      Name     : String;
      Col_Type : SData_Core.Table.Column_Type);

   function Has_Column (T : Table; Name : String) return Boolean;
   function Column_Count (T : Table) return Natural;
   function Column_Name (T : Table; I : Positive) return String;
   function Get_Column_Type
     (T : Table; Name : String) return SData_Core.Table.Column_Type;

   --  Rows
   procedure Add_Row (T : in out Table);
   function Row_Count (T : Table) return Natural;

   function Get_Value
     (T   : Table;
      Row : Positive;
      Col : String)
     return SData_Core.Values.Value;

   procedure Set_Value
     (T   : in out Table;
      Row : Positive;
      Col : String;
      Val : SData_Core.Values.Value);

   --  Snapshot bridges to/from the singleton SData_Core.Table.
   --  Snapshot_From_Current: capture the current state of the global
   --     SData_Core.Table into a new Transient_Table value. Does not
   --     modify the global state.
   --  Install_To_Current: replace the global SData_Core.Table state
   --     with the contents of the given Transient_Table. The global
   --     table is Clear-ed first.
   function Snapshot_From_Current return Table;
   procedure Install_To_Current (T : Table);

   --  Column projection / mutation

   package Name_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Unbounded_String);

   type Rename_Pair is record
      Old_Name : Unbounded_String;
      New_Name : Unbounded_String;
   end record;
   package Rename_Map_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Rename_Pair);

   --  Keep only the listed columns (case-insensitive). Names not in
   --  the table are silently ignored (matches the standalone KEEP
   --  command semantics).
   procedure Apply_Keep
     (T : in out Table; Names : Name_Vectors.Vector);

   --  Drop the listed columns. Names not present are silently ignored.
   procedure Apply_Drop
     (T : in out Table; Names : Name_Vectors.Vector);

   --  Apply a set of rename pairs simultaneously (all renames are
   --  evaluated against the original names). Raises Rename_Error if
   --  any pair has a duplicate source name, any pair has a duplicate
   --  target name, or a target name collides with an existing
   --  non-renamed column.
   procedure Apply_Rename
     (T : in out Table; Pairs : Rename_Map_Vectors.Vector);

   --  Sort rows ascending by the named columns (lexicographic on the
   --  composite key). Names that do not exist in the table are
   --  silently skipped (sorting proceeds on remaining keys).
   procedure Sort_By
     (T : in out Table; Keys : Name_Vectors.Vector);

   Rename_Error : exception;

private
   type Col_Entry is record
      Name : Unbounded_String;
      Typ  : SData_Core.Table.Column_Type;
   end record;
   package Col_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Col_Entry);

   package Value_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => SData_Core.Values.Value,
      "="          => SData_Core.Values."=");
   package Column_Data_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Value_Vectors.Vector,
      "="          => Value_Vectors."=");

   type Table is tagged record
      Cols   : Col_Vectors.Vector;
      Data   : Column_Data_Vectors.Vector;
      N_Rows : Natural := 0;
   end record;

end SData.Transient_Table;
