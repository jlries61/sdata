private package SData.Evaluator.Nav_Fns is
   procedure Register;

   --  Called by SData.Evaluator.Set_Group_Boundary before each record.
   --  Sets the values returned by BOG() and EOG() during that record's
   --  expression evaluation.
   procedure Set_Boundary (BOG, EOG : Boolean);
end SData.Evaluator.Nav_Fns;
