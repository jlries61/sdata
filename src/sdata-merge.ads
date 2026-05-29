--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later

--  SData.Merge — pure combiner algorithms operating on transient tables.
--  Each Combine_* function takes a vector of input transient tables and
--  produces a single combined transient table. Warnings are accumulated
--  in the caller-supplied vector rather than emitted to stderr directly.

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with SData.Transient_Table;

package SData.Merge is

   type Table_Access is access all SData.Transient_Table.Table;
   package Table_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Table_Access);

   package Warning_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Unbounded_String);

   --  Positional: combine by row index. Row count = max across inputs;
   --  shorter sides padded with missing. Column collisions: rightmost
   --  wins, one warning per collision.
   function Combine_Positional
     (Inputs   : Table_Vectors.Vector;
      Warnings : in out Warning_Vectors.Vector)
      return SData.Transient_Table.Table;

   --  Match merge (full outer; SAS semantics). Inputs MUST already be
   --  sorted by By_Vars. STUB in this task; implemented in Task 12.
   function Combine_Match
     (Inputs   : Table_Vectors.Vector;
      By_Vars  : SData.Transient_Table.Name_Vectors.Vector;
      Warnings : in out Warning_Vectors.Vector)
      return SData.Transient_Table.Table;

   --  Interleave: rows in BY-sorted order. STUB in this task; Task 13.
   function Combine_Interleave
     (Inputs   : Table_Vectors.Vector;
      By_Vars  : SData.Transient_Table.Name_Vectors.Vector;
      Warnings : in out Warning_Vectors.Vector)
      return SData.Transient_Table.Table;

   --  Cartesian inner join. STUB in this task; Task 14.
   function Combine_Join
     (Inputs   : Table_Vectors.Vector;
      By_Vars  : SData.Transient_Table.Name_Vectors.Vector;
      Warnings : in out Warning_Vectors.Vector)
      return SData.Transient_Table.Table;

end SData.Merge;
