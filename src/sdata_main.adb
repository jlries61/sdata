with Ada.Text_IO; use Ada.Text_IO;
with Ada.Command_Line; use Ada.Command_Line;
with Ada.Streams.Stream_IO;
with SData.Lexer; use SData.Lexer;
with SData.Parser; use SData.Parser;
with SData.AST; use SData.AST;

procedure SData_Main is
   
   function Read_File (Filename : String) return String is
      File : Ada.Streams.Stream_IO.File_Type;
      Stream : Ada.Streams.Stream_IO.Stream_Access;
   begin
      Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Filename);
      Stream := Ada.Streams.Stream_IO.Stream (File);
      declare
         Result : String (1 .. Integer (Ada.Streams.Stream_IO.Size (File)));
      begin
         String'Read (Stream, Result);
         Ada.Streams.Stream_IO.Close (File);
         return Result;
      end;
   end Read_File;

   Ctx : Parser_Context;
   Prog : Statement_Access;
   Current : Statement_Access;
begin
   if Argument_Count < 1 then
      Put_Line ("Usage: sdata_main <filename>");
      return;
   end if;

   declare
      Source : constant String := Read_File (Argument (1));
   begin
      Initialize (Ctx, Source);
      Prog := Parse_Program (Ctx);
      
      Current := Prog;
      while Current /= null loop
         Put ("Statement Kind: " & Current.Kind'Image);
         case Current.Kind is
            when Stmt_LET =>
               Put_Line (" Variable: " & Current.Var_Name (1 .. Current.Var_Len));
            when Stmt_PRINT =>
               Put_Line (" Expression: [Expr]");
            when Stmt_USE | Stmt_SAVE =>
               Put_Line (" File: " & Current.File_Path (1 .. Current.File_Len));
            when Stmt_KEEP | Stmt_DROP =>
               Put (" Vars: ");
               declare
                  V : Variable_List := Current.Vars;
               begin
                  while V /= null loop
                     Put (V.Var.Start_Name (1 .. V.Var.Start_Len));
                     if V.Var.Is_Range then
                        Put ("-" & V.Var.End_Name (1 .. V.Var.End_Len));
                     end if;
                     V := V.Next;
                     if V /= null then Put (", "); end if;
                  end loop;
                  New_Line;
               end;
            when others =>
               New_Line;
         end case;
         Current := Current.Next;
      end loop;
   end;

exception
   when E : others =>
      Put_Line ("An error occurred.");
end SData_Main;
