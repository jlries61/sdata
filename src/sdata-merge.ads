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

   --  ── Provenance ─────────────────────────────────────────────────────────
   --
   --  Each Combine_* function optionally records, for every emitted output
   --  row, which input datasets contributed to that row.  The information
   --  is returned via an in-out Provenance_Vectors.Vector: one
   --  Row_Provenance entry per emitted row, each holding a Boolean vector
   --  of length N_Inputs where Contributors(I) = True means input I
   --  contributed a real value to that output row (as opposed to being
   --  padded with missing).
   --
   --  Representation chosen: Option C (per-row record with inner Boolean
   --  vector).  This avoids fixed-size per-row arrays while remaining
   --  simpler than a flat 2-D bitmap.  The inner vector is sized to
   --  exactly N_Inputs when each entry is appended, so indexing is clean.

   package Boolean_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Boolean);

   type Row_Provenance is record
      Contributors : Boolean_Vectors.Vector;  --  Length = N_Inputs
   end record;

   package Provenance_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Row_Provenance);

   --  Positional: combine by row index. Row count = max across inputs;
   --  shorter sides padded with missing. Column collisions: rightmost
   --  wins, one warning per collision.
   function Combine_Positional
     (Inputs     : Table_Vectors.Vector;
      Warnings   : in out Warning_Vectors.Vector;
      Provenance : in out Provenance_Vectors.Vector)
      return SData.Transient_Table.Table;

   --  Match merge (full outer; SAS semantics). Inputs MUST already be
   --  sorted by By_Vars.
   function Combine_Match
     (Inputs     : Table_Vectors.Vector;
      By_Vars    : SData.Transient_Table.Name_Vectors.Vector;
      Warnings   : in out Warning_Vectors.Vector;
      Provenance : in out Provenance_Vectors.Vector)
      return SData.Transient_Table.Table;

   --  Interleave: rows in BY-sorted order.
   function Combine_Interleave
     (Inputs     : Table_Vectors.Vector;
      By_Vars    : SData.Transient_Table.Name_Vectors.Vector;
      Warnings   : in out Warning_Vectors.Vector;
      Provenance : in out Provenance_Vectors.Vector)
      return SData.Transient_Table.Table;

   --  Cartesian inner join.
   function Combine_Join
     (Inputs     : Table_Vectors.Vector;
      By_Vars    : SData.Transient_Table.Name_Vectors.Vector;
      Warnings   : in out Warning_Vectors.Vector;
      Provenance : in out Provenance_Vectors.Vector)
      return SData.Transient_Table.Table;

end SData.Merge;
