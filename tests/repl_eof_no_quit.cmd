-- Issue #69: reaching end-of-input without an explicit QUIT/END exercises a
-- distinct exit path from repl_dispatch_basic.cmd's QUIT branch -- the
-- Ada.Text_IO.End_Error handler (Flush_Pager_Buffer + New_Line + exit
-- REPL), not the Stmt_QUIT/Stmt_END dispatch branch. No QUIT statement
-- appears below; stdin simply closes after the last line.
REPEAT 2
LET X = RECNO
RUN
PRINT X
RUN
