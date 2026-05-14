separate (SData.Interpreter)
procedure Execute_IO (Stmt : Statement_Access) is
begin
   case Stmt.Kind is
      when Stmt_SUBMIT =>
         if SData.Config.Disable_Submit then
            Put_Line_Error ("Error: SUBMIT command is disabled.");
         else
         declare
            Final : constant String := Full_Path (Stmt.File_Path (1 .. Stmt.File_Len), "SUBMIT");
         begin
            if Submit_Chain.Contains (Final) then
               raise Script_Error with "Recursive SUBMIT detected: " & Final;
            end if;
            Submit_Chain.Insert (Final);
            declare
               type String_Access is access String;
               procedure Free_Buf is new Ada.Unchecked_Deallocation (String, String_Access);
               File     : Ada.Streams.Stream_IO.File_Type;
               Stream   : Ada.Streams.Stream_IO.Stream_Access;
               Contents : String_Access;  --  heap-allocated; avoids stack pressure
            begin
               Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Final);
               Contents := new String (1 .. Integer (Ada.Streams.Stream_IO.Size (File)));
               Stream := Ada.Streams.Stream_IO.Stream (File);
               String'Read (Stream, Contents.all);
               Ada.Streams.Stream_IO.Close (File);
               declare
                  Sub_Ctx  : Parser_Context;
                  Sub_Prog : Statement_Access;
               begin
                  Initialize (Sub_Ctx, Contents.all);
                  Sub_Prog := Parse_Program (Sub_Ctx);
                  Debug_Trace ("SUBMIT: entering "
                               & Stmt.File_Path (1 .. Stmt.File_Len));
                  Execute (Sub_Prog);
                  SData.AST.Free_Program (Sub_Prog);
               end;
               Free_Buf (Contents);
            exception
               when Ada.Streams.Stream_IO.Name_Error =>
                  Free_Buf (Contents);
                  Submit_Chain.Delete (Final);
                  raise Script_Error with "SUBMIT: file not found: " & Final;
               when others =>
                  Free_Buf (Contents);
                  Submit_Chain.Delete (Final);
                  raise;
            end;
            Submit_Chain.Delete (Final);
         end;
         end if;
      when Stmt_SYSTEM =>
         if SData.Config.Disable_Shell then
            Put_Line_Error ("Error: SYSTEM command is disabled.");
         else
            declare Success : Boolean;
            begin
               SData.System.Shell_Execute (Stmt.File_Path (1 .. Stmt.File_Len), Success);
            end;
         end if;
      when Stmt_OUTPUT =>
         if SData.IO.Is_Redirected then SData.IO.Close_Output; end if;
         if Stmt.File_Len > 0 then
            SData.IO.Open_Output (Full_Path (Stmt.File_Path (1 .. Stmt.File_Len), "OUTPUT"));
         end if;
         if Stmt.Output_FMT_Len > 0 then
            SData.Config.Runtime.Options_TXTFMT := (others => ' ');
            SData.Config.Runtime.Options_TXTFMT (1 .. Stmt.Output_FMT_Len) :=
               Stmt.Output_FMT_Val (1 .. Stmt.Output_FMT_Len);
            SData.Config.Runtime.Options_TXTFMT_Len := Stmt.Output_FMT_Len;
         end if;
         if Stmt.Output_CHARSET_Len > 0 then
            SData.Config.Runtime.Options_CHARSET := (others => ' ');
            SData.Config.Runtime.Options_CHARSET (1 .. Stmt.Output_CHARSET_Len) :=
               Stmt.Output_CHARSET_Val (1 .. Stmt.Output_CHARSET_Len);
            SData.Config.Runtime.Options_CHARSET_Len := Stmt.Output_CHARSET_Len;
         end if;
      when Stmt_FPATH =>
         declare
            Path      : constant String  := (if Stmt.File_Len > 0 then Stmt.File_Path (1 .. Stmt.File_Len) else "");
            Reset_All : constant Boolean := not (Stmt.Use_Flag or Stmt.Save_Flag or Stmt.Submit_Flag or Stmt.Output_Flag);
         begin
            if Reset_All or Stmt.Use_Flag    then SData.Config.Runtime.FPath_Use    := To_Unbounded_String (Path); end if;
            if Reset_All or Stmt.Save_Flag   then SData.Config.Runtime.FPath_Save   := To_Unbounded_String (Path); end if;
            if Reset_All or Stmt.Submit_Flag then SData.Config.Runtime.FPath_Submit := To_Unbounded_String (Path); end if;
            if Reset_All or Stmt.Output_Flag then SData.Config.Runtime.FPath_Output := To_Unbounded_String (Path); end if;
         end;
      when others => null;
   end case;
end Execute_IO;
