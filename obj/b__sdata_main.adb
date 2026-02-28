pragma Warnings (Off);
pragma Ada_95;
pragma Source_File_Name (ada_main, Spec_File_Name => "b__sdata_main.ads");
pragma Source_File_Name (ada_main, Body_File_Name => "b__sdata_main.adb");
pragma Suppress (Overflow_Check);
with Ada.Exceptions;

package body ada_main is

   E075 : Short_Integer; pragma Import (Ada, E075, "system__os_lib_E");
   E011 : Short_Integer; pragma Import (Ada, E011, "ada__exceptions_E");
   E015 : Short_Integer; pragma Import (Ada, E015, "system__soft_links_E");
   E024 : Short_Integer; pragma Import (Ada, E024, "system__exception_table_E");
   E040 : Short_Integer; pragma Import (Ada, E040, "ada__containers_E");
   E070 : Short_Integer; pragma Import (Ada, E070, "ada__io_exceptions_E");
   E031 : Short_Integer; pragma Import (Ada, E031, "ada__numerics_E");
   E055 : Short_Integer; pragma Import (Ada, E055, "ada__strings_E");
   E057 : Short_Integer; pragma Import (Ada, E057, "ada__strings__maps_E");
   E060 : Short_Integer; pragma Import (Ada, E060, "ada__strings__maps__constants_E");
   E045 : Short_Integer; pragma Import (Ada, E045, "interfaces__c_E");
   E025 : Short_Integer; pragma Import (Ada, E025, "system__exceptions_E");
   E086 : Short_Integer; pragma Import (Ada, E086, "system__object_reader_E");
   E050 : Short_Integer; pragma Import (Ada, E050, "system__dwarf_lines_E");
   E017 : Short_Integer; pragma Import (Ada, E017, "system__soft_links__initialize_E");
   E039 : Short_Integer; pragma Import (Ada, E039, "system__traceback__symbolic_E");
   E109 : Short_Integer; pragma Import (Ada, E109, "ada__strings__utf_encoding_E");
   E117 : Short_Integer; pragma Import (Ada, E117, "ada__tags_E");
   E107 : Short_Integer; pragma Import (Ada, E107, "ada__strings__text_buffers_E");
   E158 : Short_Integer; pragma Import (Ada, E158, "gnat_E");
   E105 : Short_Integer; pragma Import (Ada, E105, "ada__streams_E");
   E141 : Short_Integer; pragma Import (Ada, E141, "system__file_control_block_E");
   E136 : Short_Integer; pragma Import (Ada, E136, "system__finalization_root_E");
   E134 : Short_Integer; pragma Import (Ada, E134, "ada__finalization_E");
   E133 : Short_Integer; pragma Import (Ada, E133, "system__file_io_E");
   E127 : Short_Integer; pragma Import (Ada, E127, "ada__streams__stream_io_E");
   E225 : Short_Integer; pragma Import (Ada, E225, "system__storage_pools_E");
   E227 : Short_Integer; pragma Import (Ada, E227, "system__storage_pools__subpools_E");
   E199 : Short_Integer; pragma Import (Ada, E199, "ada__strings__unbounded_E");
   E180 : Short_Integer; pragma Import (Ada, E180, "ada__calendar_E");
   E143 : Short_Integer; pragma Import (Ada, E143, "ada__text_io_E");
   E280 : Short_Integer; pragma Import (Ada, E280, "ada__text_io__text_streams_E");
   E322 : Short_Integer; pragma Import (Ada, E322, "gnat__directory_operations_E");
   E341 : Short_Integer; pragma Import (Ada, E341, "system__direct_io_E");
   E221 : Short_Integer; pragma Import (Ada, E221, "system__pool_global_E");
   E178 : Short_Integer; pragma Import (Ada, E178, "system__random_seed_E");
   E244 : Short_Integer; pragma Import (Ada, E244, "unicode_E");
   E339 : Short_Integer; pragma Import (Ada, E339, "bzip2_E");
   E343 : Short_Integer; pragma Import (Ada, E343, "bzip2__decoding_E");
   E187 : Short_Integer; pragma Import (Ada, E187, "error_function_E");
   E189 : Short_Integer; pragma Import (Ada, E189, "gamma_function_E");
   E346 : Short_Integer; pragma Import (Ada, E346, "lzma__decoding_E");
   E191 : Short_Integer; pragma Import (Ada, E191, "phi_function_E");
   E185 : Short_Integer; pragma Import (Ada, E185, "beta_function_E");
   E193 : Short_Integer; pragma Import (Ada, E193, "generic_random_functions_E");
   E261 : Short_Integer; pragma Import (Ada, E261, "sax__htable_E");
   E268 : Short_Integer; pragma Import (Ada, E268, "sax__pointers_E");
   E373 : Short_Integer; pragma Import (Ada, E373, "sdata__lexer_E");
   E369 : Short_Integer; pragma Import (Ada, E369, "sdata__parser_E");
   E172 : Short_Integer; pragma Import (Ada, E172, "sdata__statistics_E");
   E211 : Short_Integer; pragma Import (Ada, E211, "sdata__values_E");
   E197 : Short_Integer; pragma Import (Ada, E197, "sdata__table_E");
   E233 : Short_Integer; pragma Import (Ada, E233, "sdata__variables_E");
   E161 : Short_Integer; pragma Import (Ada, E161, "sdata__evaluator_E");
   E257 : Short_Integer; pragma Import (Ada, E257, "unicode__ccs_E");
   E284 : Short_Integer; pragma Import (Ada, E284, "unicode__ccs__iso_8859_1_E");
   E286 : Short_Integer; pragma Import (Ada, E286, "unicode__ccs__iso_8859_15_E");
   E291 : Short_Integer; pragma Import (Ada, E291, "unicode__ccs__iso_8859_2_E");
   E294 : Short_Integer; pragma Import (Ada, E294, "unicode__ccs__iso_8859_3_E");
   E296 : Short_Integer; pragma Import (Ada, E296, "unicode__ccs__iso_8859_4_E");
   E298 : Short_Integer; pragma Import (Ada, E298, "unicode__ccs__windows_1251_E");
   E303 : Short_Integer; pragma Import (Ada, E303, "unicode__ccs__windows_1252_E");
   E253 : Short_Integer; pragma Import (Ada, E253, "unicode__ces_E");
   E263 : Short_Integer; pragma Import (Ada, E263, "sax__symbols_E");
   E320 : Short_Integer; pragma Import (Ada, E320, "sax__locators_E");
   E318 : Short_Integer; pragma Import (Ada, E318, "sax__exceptions_E");
   E255 : Short_Integer; pragma Import (Ada, E255, "unicode__ces__utf32_E");
   E306 : Short_Integer; pragma Import (Ada, E306, "unicode__ces__basic_8bit_E");
   E308 : Short_Integer; pragma Import (Ada, E308, "unicode__ces__utf16_E");
   E259 : Short_Integer; pragma Import (Ada, E259, "unicode__ces__utf8_E");
   E316 : Short_Integer; pragma Import (Ada, E316, "sax__models_E");
   E314 : Short_Integer; pragma Import (Ada, E314, "sax__attributes_E");
   E270 : Short_Integer; pragma Import (Ada, E270, "sax__utils_E");
   E240 : Short_Integer; pragma Import (Ada, E240, "dom__core_E");
   E282 : Short_Integer; pragma Import (Ada, E282, "unicode__encodings_E");
   E278 : Short_Integer; pragma Import (Ada, E278, "dom__core__nodes_E");
   E276 : Short_Integer; pragma Import (Ada, E276, "dom__core__attrs_E");
   E312 : Short_Integer; pragma Import (Ada, E312, "dom__core__character_datas_E");
   E272 : Short_Integer; pragma Import (Ada, E272, "dom__core__documents_E");
   E274 : Short_Integer; pragma Import (Ada, E274, "dom__core__elements_E");
   E327 : Short_Integer; pragma Import (Ada, E327, "input_sources_E");
   E329 : Short_Integer; pragma Import (Ada, E329, "input_sources__file_E");
   E331 : Short_Integer; pragma Import (Ada, E331, "input_sources__strings_E");
   E325 : Short_Integer; pragma Import (Ada, E325, "sax__readers_E");
   E310 : Short_Integer; pragma Import (Ada, E310, "dom__readers_E");
   E365 : Short_Integer; pragma Import (Ada, E365, "zip_streams_E");
   E351 : Short_Integer; pragma Import (Ada, E351, "zip_E");
   E363 : Short_Integer; pragma Import (Ada, E363, "zip__headers_E");
   E367 : Short_Integer; pragma Import (Ada, E367, "zip__crc_crypto_E");
   E335 : Short_Integer; pragma Import (Ada, E335, "unzip_E");
   E337 : Short_Integer; pragma Import (Ada, E337, "unzip__decompress_E");
   E349 : Short_Integer; pragma Import (Ada, E349, "unzip__decompress__huffman_E");
   E237 : Short_Integer; pragma Import (Ada, E237, "sdata__file_io_E");
   E148 : Short_Integer; pragma Import (Ada, E148, "sdata__interpreter_E");

   Sec_Default_Sized_Stacks : array (1 .. 1) of aliased System.Secondary_Stack.SS_Stack (System.Parameters.Runtime_Default_Sec_Stack_Size);

   Local_Priority_Specific_Dispatching : constant String := "";
   Local_Interrupt_States : constant String := "";

   Is_Elaborated : Boolean := False;

   procedure finalize_library is
   begin
      declare
         procedure F1;
         pragma Import (Ada, F1, "sdata__interpreter__finalize_body");
      begin
         E148 := E148 - 1;
         F1;
      end;
      E335 := E335 - 1;
      declare
         procedure F2;
         pragma Import (Ada, F2, "unzip__finalize_spec");
      begin
         F2;
      end;
      E351 := E351 - 1;
      declare
         procedure F3;
         pragma Import (Ada, F3, "zip__finalize_spec");
      begin
         F3;
      end;
      E365 := E365 - 1;
      declare
         procedure F4;
         pragma Import (Ada, F4, "zip_streams__finalize_spec");
      begin
         F4;
      end;
      E310 := E310 - 1;
      declare
         procedure F5;
         pragma Import (Ada, F5, "dom__readers__finalize_spec");
      begin
         F5;
      end;
      E325 := E325 - 1;
      declare
         procedure F6;
         pragma Import (Ada, F6, "sax__readers__finalize_spec");
      begin
         F6;
      end;
      E331 := E331 - 1;
      declare
         procedure F7;
         pragma Import (Ada, F7, "input_sources__strings__finalize_spec");
      begin
         F7;
      end;
      E329 := E329 - 1;
      declare
         procedure F8;
         pragma Import (Ada, F8, "input_sources__file__finalize_spec");
      begin
         F8;
      end;
      E327 := E327 - 1;
      declare
         procedure F9;
         pragma Import (Ada, F9, "input_sources__finalize_spec");
      begin
         F9;
      end;
      E240 := E240 - 1;
      declare
         procedure F10;
         pragma Import (Ada, F10, "dom__core__finalize_spec");
      begin
         F10;
      end;
      E270 := E270 - 1;
      declare
         procedure F11;
         pragma Import (Ada, F11, "sax__utils__finalize_spec");
      begin
         F11;
      end;
      E314 := E314 - 1;
      declare
         procedure F12;
         pragma Import (Ada, F12, "sax__attributes__finalize_spec");
      begin
         F12;
      end;
      E318 := E318 - 1;
      declare
         procedure F13;
         pragma Import (Ada, F13, "sax__exceptions__finalize_spec");
      begin
         F13;
      end;
      E263 := E263 - 1;
      declare
         procedure F14;
         pragma Import (Ada, F14, "sax__symbols__finalize_spec");
      begin
         F14;
      end;
      E233 := E233 - 1;
      declare
         procedure F15;
         pragma Import (Ada, F15, "sdata__variables__finalize_spec");
      begin
         F15;
      end;
      E197 := E197 - 1;
      declare
         procedure F16;
         pragma Import (Ada, F16, "sdata__table__finalize_spec");
      begin
         F16;
      end;
      E268 := E268 - 1;
      declare
         procedure F17;
         pragma Import (Ada, F17, "sax__pointers__finalize_spec");
      begin
         F17;
      end;
      E221 := E221 - 1;
      declare
         procedure F18;
         pragma Import (Ada, F18, "system__pool_global__finalize_spec");
      begin
         F18;
      end;
      E341 := E341 - 1;
      declare
         procedure F19;
         pragma Import (Ada, F19, "system__direct_io__finalize_spec");
      begin
         F19;
      end;
      E143 := E143 - 1;
      declare
         procedure F20;
         pragma Import (Ada, F20, "ada__text_io__finalize_spec");
      begin
         F20;
      end;
      E199 := E199 - 1;
      declare
         procedure F21;
         pragma Import (Ada, F21, "ada__strings__unbounded__finalize_spec");
      begin
         F21;
      end;
      E227 := E227 - 1;
      declare
         procedure F22;
         pragma Import (Ada, F22, "system__storage_pools__subpools__finalize_spec");
      begin
         F22;
      end;
      E127 := E127 - 1;
      declare
         procedure F23;
         pragma Import (Ada, F23, "ada__streams__stream_io__finalize_spec");
      begin
         F23;
      end;
      declare
         procedure F24;
         pragma Import (Ada, F24, "system__file_io__finalize_body");
      begin
         E133 := E133 - 1;
         F24;
      end;
      declare
         procedure Reraise_Library_Exception_If_Any;
            pragma Import (Ada, Reraise_Library_Exception_If_Any, "__gnat_reraise_library_exception_if_any");
      begin
         Reraise_Library_Exception_If_Any;
      end;
   end finalize_library;

   procedure adafinal is
      procedure s_stalib_adafinal;
      pragma Import (Ada, s_stalib_adafinal, "system__standard_library__adafinal");

      procedure Runtime_Finalize;
      pragma Import (C, Runtime_Finalize, "__gnat_runtime_finalize");

   begin
      if not Is_Elaborated then
         return;
      end if;
      Is_Elaborated := False;
      Runtime_Finalize;
      s_stalib_adafinal;
   end adafinal;

   type No_Param_Proc is access procedure;
   pragma Favor_Top_Level (No_Param_Proc);

   procedure adainit is
      Main_Priority : Integer;
      pragma Import (C, Main_Priority, "__gl_main_priority");
      Time_Slice_Value : Integer;
      pragma Import (C, Time_Slice_Value, "__gl_time_slice_val");
      WC_Encoding : Character;
      pragma Import (C, WC_Encoding, "__gl_wc_encoding");
      Locking_Policy : Character;
      pragma Import (C, Locking_Policy, "__gl_locking_policy");
      Queuing_Policy : Character;
      pragma Import (C, Queuing_Policy, "__gl_queuing_policy");
      Task_Dispatching_Policy : Character;
      pragma Import (C, Task_Dispatching_Policy, "__gl_task_dispatching_policy");
      Priority_Specific_Dispatching : System.Address;
      pragma Import (C, Priority_Specific_Dispatching, "__gl_priority_specific_dispatching");
      Num_Specific_Dispatching : Integer;
      pragma Import (C, Num_Specific_Dispatching, "__gl_num_specific_dispatching");
      Main_CPU : Integer;
      pragma Import (C, Main_CPU, "__gl_main_cpu");
      Interrupt_States : System.Address;
      pragma Import (C, Interrupt_States, "__gl_interrupt_states");
      Num_Interrupt_States : Integer;
      pragma Import (C, Num_Interrupt_States, "__gl_num_interrupt_states");
      Unreserve_All_Interrupts : Integer;
      pragma Import (C, Unreserve_All_Interrupts, "__gl_unreserve_all_interrupts");
      Detect_Blocking : Integer;
      pragma Import (C, Detect_Blocking, "__gl_detect_blocking");
      Default_Stack_Size : Integer;
      pragma Import (C, Default_Stack_Size, "__gl_default_stack_size");
      Default_Secondary_Stack_Size : System.Parameters.Size_Type;
      pragma Import (C, Default_Secondary_Stack_Size, "__gnat_default_ss_size");
      Bind_Env_Addr : System.Address;
      pragma Import (C, Bind_Env_Addr, "__gl_bind_env_addr");
      Interrupts_Default_To_System : Integer;
      pragma Import (C, Interrupts_Default_To_System, "__gl_interrupts_default_to_system");

      procedure Runtime_Initialize (Install_Handler : Integer);
      pragma Import (C, Runtime_Initialize, "__gnat_runtime_initialize");

      Finalize_Library_Objects : No_Param_Proc;
      pragma Import (C, Finalize_Library_Objects, "__gnat_finalize_library_objects");
      Binder_Sec_Stacks_Count : Natural;
      pragma Import (Ada, Binder_Sec_Stacks_Count, "__gnat_binder_ss_count");
      Default_Sized_SS_Pool : System.Address;
      pragma Import (Ada, Default_Sized_SS_Pool, "__gnat_default_ss_pool");

   begin
      if Is_Elaborated then
         return;
      end if;
      Is_Elaborated := True;
      Main_Priority := -1;
      Time_Slice_Value := -1;
      WC_Encoding := 'b';
      Locking_Policy := ' ';
      Queuing_Policy := ' ';
      Task_Dispatching_Policy := ' ';
      Priority_Specific_Dispatching :=
        Local_Priority_Specific_Dispatching'Address;
      Num_Specific_Dispatching := 0;
      Main_CPU := -1;
      Interrupt_States := Local_Interrupt_States'Address;
      Num_Interrupt_States := 0;
      Unreserve_All_Interrupts := 0;
      Detect_Blocking := 0;
      Default_Stack_Size := -1;

      ada_main'Elab_Body;
      Default_Secondary_Stack_Size := System.Parameters.Runtime_Default_Sec_Stack_Size;
      Binder_Sec_Stacks_Count := 1;
      Default_Sized_SS_Pool := Sec_Default_Sized_Stacks'Address;

      Runtime_Initialize (1);

      Finalize_Library_Objects := finalize_library'access;

      Ada.Exceptions'Elab_Spec;
      System.Soft_Links'Elab_Spec;
      System.Exception_Table'Elab_Body;
      E024 := E024 + 1;
      Ada.Containers'Elab_Spec;
      E040 := E040 + 1;
      Ada.Io_Exceptions'Elab_Spec;
      E070 := E070 + 1;
      Ada.Numerics'Elab_Spec;
      E031 := E031 + 1;
      Ada.Strings'Elab_Spec;
      E055 := E055 + 1;
      Ada.Strings.Maps'Elab_Spec;
      E057 := E057 + 1;
      Ada.Strings.Maps.Constants'Elab_Spec;
      E060 := E060 + 1;
      Interfaces.C'Elab_Spec;
      E045 := E045 + 1;
      System.Exceptions'Elab_Spec;
      E025 := E025 + 1;
      System.Object_Reader'Elab_Spec;
      E086 := E086 + 1;
      System.Dwarf_Lines'Elab_Spec;
      E050 := E050 + 1;
      System.Os_Lib'Elab_Body;
      E075 := E075 + 1;
      System.Soft_Links.Initialize'Elab_Body;
      E017 := E017 + 1;
      E015 := E015 + 1;
      System.Traceback.Symbolic'Elab_Body;
      E039 := E039 + 1;
      E011 := E011 + 1;
      Ada.Strings.Utf_Encoding'Elab_Spec;
      E109 := E109 + 1;
      Ada.Tags'Elab_Spec;
      Ada.Tags'Elab_Body;
      E117 := E117 + 1;
      Ada.Strings.Text_Buffers'Elab_Spec;
      E107 := E107 + 1;
      Gnat'Elab_Spec;
      E158 := E158 + 1;
      Ada.Streams'Elab_Spec;
      E105 := E105 + 1;
      System.File_Control_Block'Elab_Spec;
      E141 := E141 + 1;
      System.Finalization_Root'Elab_Spec;
      E136 := E136 + 1;
      Ada.Finalization'Elab_Spec;
      E134 := E134 + 1;
      System.File_Io'Elab_Body;
      E133 := E133 + 1;
      Ada.Streams.Stream_Io'Elab_Spec;
      E127 := E127 + 1;
      System.Storage_Pools'Elab_Spec;
      E225 := E225 + 1;
      System.Storage_Pools.Subpools'Elab_Spec;
      E227 := E227 + 1;
      Ada.Strings.Unbounded'Elab_Spec;
      E199 := E199 + 1;
      Ada.Calendar'Elab_Spec;
      Ada.Calendar'Elab_Body;
      E180 := E180 + 1;
      Ada.Text_Io'Elab_Spec;
      Ada.Text_Io'Elab_Body;
      E143 := E143 + 1;
      Ada.Text_Io.Text_Streams'Elab_Spec;
      E280 := E280 + 1;
      Gnat.Directory_Operations'Elab_Spec;
      Gnat.Directory_Operations'Elab_Body;
      E322 := E322 + 1;
      System.Direct_Io'Elab_Spec;
      E341 := E341 + 1;
      System.Pool_Global'Elab_Spec;
      E221 := E221 + 1;
      System.Random_Seed'Elab_Body;
      E178 := E178 + 1;
      Unicode'Elab_Body;
      E244 := E244 + 1;
      E339 := E339 + 1;
      E343 := E343 + 1;
      E187 := E187 + 1;
      E189 := E189 + 1;
      E346 := E346 + 1;
      E191 := E191 + 1;
      E185 := E185 + 1;
      E193 := E193 + 1;
      E261 := E261 + 1;
      Sax.Pointers'Elab_Spec;
      Sax.Pointers'Elab_Body;
      E268 := E268 + 1;
      E373 := E373 + 1;
      E369 := E369 + 1;
      SDATA.STATISTICS'ELAB_SPEC;
      E172 := E172 + 1;
      E211 := E211 + 1;
      Sdata.Table'Elab_Spec;
      E197 := E197 + 1;
      Sdata.Variables'Elab_Spec;
      E233 := E233 + 1;
      E161 := E161 + 1;
      Unicode.Ccs'Elab_Spec;
      E257 := E257 + 1;
      E284 := E284 + 1;
      E286 := E286 + 1;
      E291 := E291 + 1;
      E294 := E294 + 1;
      E296 := E296 + 1;
      E298 := E298 + 1;
      E303 := E303 + 1;
      Unicode.Ces'Elab_Spec;
      E253 := E253 + 1;
      Sax.Symbols'Elab_Spec;
      Sax.Symbols'Elab_Body;
      E263 := E263 + 1;
      E320 := E320 + 1;
      Sax.Exceptions'Elab_Spec;
      Sax.Exceptions'Elab_Body;
      E318 := E318 + 1;
      E255 := E255 + 1;
      E306 := E306 + 1;
      E308 := E308 + 1;
      E259 := E259 + 1;
      Sax.Models'Elab_Spec;
      E316 := E316 + 1;
      Sax.Attributes'Elab_Spec;
      Sax.Attributes'Elab_Body;
      E314 := E314 + 1;
      Sax.Utils'Elab_Spec;
      Sax.Utils'Elab_Body;
      E270 := E270 + 1;
      DOM.CORE'ELAB_SPEC;
      E240 := E240 + 1;
      E282 := E282 + 1;
      E278 := E278 + 1;
      E276 := E276 + 1;
      E312 := E312 + 1;
      E274 := E274 + 1;
      E272 := E272 + 1;
      Input_Sources'Elab_Spec;
      Input_Sources'Elab_Body;
      E327 := E327 + 1;
      Input_Sources.File'Elab_Spec;
      Input_Sources.File'Elab_Body;
      E329 := E329 + 1;
      Input_Sources.Strings'Elab_Spec;
      Input_Sources.Strings'Elab_Body;
      E331 := E331 + 1;
      Sax.Readers'Elab_Spec;
      Sax.Readers'Elab_Body;
      E325 := E325 + 1;
      DOM.READERS'ELAB_SPEC;
      DOM.READERS'ELAB_BODY;
      E310 := E310 + 1;
      Zip_Streams'Elab_Spec;
      Zip_Streams'Elab_Body;
      E365 := E365 + 1;
      Zip'Elab_Spec;
      Zip.Headers'Elab_Spec;
      E363 := E363 + 1;
      Zip'Elab_Body;
      E351 := E351 + 1;
      E367 := E367 + 1;
      Unzip'Elab_Spec;
      E335 := E335 + 1;
      Unzip.Decompress.Huffman'Elab_Spec;
      E349 := E349 + 1;
      E337 := E337 + 1;
      E237 := E237 + 1;
      Sdata.Interpreter'Elab_Body;
      E148 := E148 + 1;
   end adainit;

   procedure Ada_Main_Program;
   pragma Import (Ada, Ada_Main_Program, "_ada_sdata_main");

   function main
     (argc : Integer;
      argv : System.Address;
      envp : System.Address)
      return Integer
   is
      procedure Initialize (Addr : System.Address);
      pragma Import (C, Initialize, "__gnat_initialize");

      procedure Finalize;
      pragma Import (C, Finalize, "__gnat_finalize");
      SEH : aliased array (1 .. 2) of Integer;

      Ensure_Reference : aliased System.Address := Ada_Main_Program_Name'Address;
      pragma Volatile (Ensure_Reference);

   begin
      if gnat_argc = 0 then
         gnat_argc := argc;
         gnat_argv := argv;
      end if;
      gnat_envp := envp;

      Initialize (SEH'Address);
      adainit;
      Ada_Main_Program;
      adafinal;
      Finalize;
      return (gnat_exit_status);
   end;

--  BEGIN Object file/option list
   --   /home/jries/Develop/zipada_61.0.0_54fc9836/obj/fast/bzip2.o
   --   /home/jries/Develop/zipada_61.0.0_54fc9836/obj/fast/bzip2-decoding.o
   --   /home/jries/Develop/mathpaqs_20260205.0.0_abed7ef9/obj_fast/error_function.o
   --   /home/jries/Develop/mathpaqs_20260205.0.0_abed7ef9/obj_fast/gamma_function.o
   --   /home/jries/Develop/zipada_61.0.0_54fc9836/obj/fast/lzma.o
   --   /home/jries/Develop/zipada_61.0.0_54fc9836/obj/fast/lzma-decoding.o
   --   /home/jries/Develop/mathpaqs_20260205.0.0_abed7ef9/obj_fast/phi_function.o
   --   /home/jries/Develop/mathpaqs_20260205.0.0_abed7ef9/obj_fast/beta_function.o
   --   /home/jries/Develop/mathpaqs_20260205.0.0_abed7ef9/obj_fast/generic_random_functions.o
   --   /home/jries/Develop/sdata/obj/sdata.o
   --   /home/jries/Develop/sdata/obj/sdata-ast.o
   --   /home/jries/Develop/sdata/obj/sdata-config.o
   --   /home/jries/Develop/sdata/obj/sdata-lexer.o
   --   /home/jries/Develop/sdata/obj/sdata-parser.o
   --   /home/jries/Develop/sdata/obj/sdata-statistics.o
   --   /home/jries/Develop/sdata/obj/sdata-values.o
   --   /home/jries/Develop/sdata/obj/sdata-table.o
   --   /home/jries/Develop/sdata/obj/sdata-variables.o
   --   /home/jries/Develop/sdata/obj/sdata-evaluator.o
   --   /home/jries/Develop/zipada_61.0.0_54fc9836/obj/fast/zip_streams.o
   --   /home/jries/Develop/zipada_61.0.0_54fc9836/obj/fast/zip-headers.o
   --   /home/jries/Develop/zipada_61.0.0_54fc9836/obj/fast/zip.o
   --   /home/jries/Develop/zipada_61.0.0_54fc9836/obj/fast/zip-crc_crypto.o
   --   /home/jries/Develop/zipada_61.0.0_54fc9836/obj/fast/unzip.o
   --   /home/jries/Develop/zipada_61.0.0_54fc9836/obj/fast/unzip-decompress-huffman.o
   --   /home/jries/Develop/zipada_61.0.0_54fc9836/obj/fast/unzip-decompress.o
   --   /home/jries/Develop/sdata/obj/sdata-file_io.o
   --   /home/jries/Develop/sdata/obj/sdata-interpreter.o
   --   /home/jries/Develop/sdata/obj/sdata_main.o
   --   -L/home/jries/Develop/sdata/obj/
   --   -L/home/jries/Develop/sdata/obj/
   --   -L/home/jries/Develop/zipada_61.0.0_54fc9836/obj/fast/
   --   -L/home/jries/Develop/xmlada_26.0.0_b140ed4a/dom/lib/static/
   --   -L/home/jries/Develop/xmlada_26.0.0_b140ed4a/sax/lib/static/
   --   -L/home/jries/Develop/xmlada_26.0.0_b140ed4a/unicode/lib/static/
   --   -L/home/jries/Develop/xmlada_26.0.0_b140ed4a/input_sources/lib/static/
   --   -L/home/jries/Develop/mathpaqs_20260205.0.0_abed7ef9/obj_fast/
   --   -L/home/jries/Develop/sciada_0.4.0_af24740d/lib/sciada/static/
   --   -L/usr/lib64/gcc/x86_64-suse-linux/15/adalib/
   --   -static
   --   -lgnat
   --   -lm
   --   -ldl
--  END Object file/option list   

end ada_main;
