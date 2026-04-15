package body SData.Config is

   procedure Reset_Runtime_State is
      Defaults : constant Runtime_State_Record := (others => <>);
   begin
      Runtime := Defaults;
   end Reset_Runtime_State;

end SData.Config;
