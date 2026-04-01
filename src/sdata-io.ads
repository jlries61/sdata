package SData.IO is

   procedure Put (Item : String);
   procedure Put_Line (Item : String);
   procedure New_Line;

   procedure Put_Error (Item : String);
   procedure Put_Line_Error (Item : String);

   procedure Open_Output (Filename : String);
   procedure Close_Output;
   function Is_Redirected return Boolean;

   procedure Set_Interactive (Val : Boolean);
   procedure Set_Local_Echo (Val : Boolean);

end SData.IO;
