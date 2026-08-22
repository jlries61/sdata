-- PC-1: Get_Array_Element must raise on a reference to an array that is no
-- longer defined. Needs REPL (piped stdin) to reach it -- batch mode parses
-- V(2) before ARRAY V A B C runs, so it's a harmless missing function call.
ARRAY V A B C
PRINT V(2)
ARRAY V
RUN
QUIT
