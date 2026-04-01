with Ada.Text_IO;
with SData.Config;

package body SData.IO is

   Redirect_File : Ada.Text_IO.File_Type;
   Redirected    : Boolean := False;
   Local_Echo    : Boolean := True;

   -- Pager State
   Lines_On_Page : constant := 24;
   Lines_Printed : Natural := 0;
   Interactive_Mode : Boolean := False;

   procedure Set_Interactive (Val : Boolean) is
   begin
      Interactive_Mode := Val;
   end Set_Interactive;

   procedure Set_Local_Echo (Val : Boolean) is
   begin
      Local_Echo := Val;
   end Set_Local_Echo;

   procedure Check_Pager is
      Dummy : String (1 .. 10);
      Last  : Natural;
   begin
      if Interactive_Mode and then Local_Echo and then Lines_Printed >= Lines_On_Page then
         Ada.Text_IO.Put ("-- More -- (Press Enter)");
         begin
            Ada.Text_IO.Get_Line (Dummy, Last);
         exception
            when others => null;
         end;
         Lines_Printed := 0;
      end if;
   end Check_Pager;

   procedure Put (Item : String) is
   begin
      if Redirected then
         Ada.Text_IO.Put (Redirect_File, Item);
         Ada.Text_IO.Flush (Redirect_File);
      end if;

      if Local_Echo and then not SData.Config.Quiet_Mode then
         Ada.Text_IO.Put (Ada.Text_IO.Standard_Output, Item);
         Ada.Text_IO.Flush (Ada.Text_IO.Standard_Output);
      end if;
   end Put;

   procedure Put_Line (Item : String) is
   begin
      if Redirected then
         Ada.Text_IO.Put_Line (Redirect_File, Item);
         Ada.Text_IO.Flush (Redirect_File);
      end if;

      if Local_Echo and then not SData.Config.Quiet_Mode then
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Output, Item);
         Lines_Printed := Lines_Printed + 1;
         Check_Pager;
      end if;
   end Put_Line;

   procedure New_Line is
   begin
      if Redirected then
         Ada.Text_IO.New_Line (Redirect_File);
         Ada.Text_IO.Flush (Redirect_File);
      end if;

      if Local_Echo and then not SData.Config.Quiet_Mode then
         Ada.Text_IO.New_Line (Ada.Text_IO.Standard_Output);
         Lines_Printed := Lines_Printed + 1;
         Check_Pager;
      end if;
   end New_Line;

   procedure Put_Error (Item : String) is
   begin
      if Redirected then
         Ada.Text_IO.Put (Redirect_File, Item);
         Ada.Text_IO.Flush (Redirect_File);
      end if;

      Ada.Text_IO.Put (Ada.Text_IO.Standard_Error, Item);
      Ada.Text_IO.Flush (Ada.Text_IO.Standard_Error);
   end Put_Error;

   procedure Put_Line_Error (Item : String) is
   begin
      if Redirected then
         Ada.Text_IO.Put_Line (Redirect_File, Item);
         Ada.Text_IO.Flush (Redirect_File);
      end if;

      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, Item);
   end Put_Line_Error;

   procedure Open_Output (Filename : String) is
   begin
      if Redirected then
         Close_Output;
      end if;
      Ada.Text_IO.Create (Redirect_File, Ada.Text_IO.Out_File, Filename);
      Redirected := True;
   end Open_Output;

   procedure Close_Output is
   begin
      if Redirected then
         Ada.Text_IO.Close (Redirect_File);
         Redirected := False;
      end if;
   end Close_Output;

   function Is_Redirected return Boolean is
   begin
      return Redirected;
   end Is_Redirected;

end SData.IO;
