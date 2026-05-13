with Ada.Containers.Vectors;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with DOM.Core;
with SData.Values; use SData.Values;
with SData.Table;  use SData.Table;

private package SData.File_IO.Helpers is

   package Name_Vecs is new Ada.Containers.Vectors (Positive, Unbounded_String);
   type Column_Type_Array is array (Positive range <>) of Column_Type;

   function Get_Text (N : DOM.Core.Node) return String;
   function Detect_Inf (S : String) return Value;
   procedure Apply_Dollar_Override
      (Col_Name_Vec : Name_Vecs.Vector;
       Col_Types    : in out Column_Type_Array);
   function Safe_Name (S : String; Default : String) return String;
   function Col_To_Letters (Col : Positive) return String;
   function Escape_XML (S : String) return String;
   function Has_Formulas_XML (Temp_File : String; Is_ODF : Boolean) return Boolean;
   function Convert_Via_LibreOffice (File_Name : String; Fmt : Format_Type) return String;

end SData.File_IO.Helpers;
