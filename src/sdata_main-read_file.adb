--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

separate (SData_Main)
--  Helper to read the entire contents of a file into a single String buffer.
--  The buffer is heap-allocated to avoid placing large scripts on the stack.
function Read_File (Filename : String) return String is
   type String_Access is access String;
   procedure Free_Buf is new Ada.Unchecked_Deallocation (String, String_Access);
   File   : Ada.Streams.Stream_IO.File_Type;
   Stream : Ada.Streams.Stream_IO.Stream_Access;
begin
   begin
      Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Filename);
   exception
      when Ada.Streams.Stream_IO.Name_Error =>
         raise SData.Script_Error with "cannot open """ & Filename & """: file not found";
      when Ada.Streams.Stream_IO.Use_Error =>
         raise SData.Script_Error with "cannot open """ & Filename & """: permission denied";
   end;
   declare
      Size : constant Ada.Streams.Stream_IO.Count := Ada.Streams.Stream_IO.Size (File);
   begin
      if Integer (Size) = 0 then
         Ada.Streams.Stream_IO.Close (File);
         return "";
      end if;
      Stream := Ada.Streams.Stream_IO.Stream (File);
      declare
         Buf : String_Access := new String (1 .. Integer (Size));
      begin
         String'Read (Stream, Buf.all);
         Ada.Streams.Stream_IO.Close (File);
         declare
            Ret : constant String := Buf.all;  --  copy; Buf can now be freed
         begin
            Free_Buf (Buf);
            return Ret;
         end;
      end;
   end;
end Read_File;
