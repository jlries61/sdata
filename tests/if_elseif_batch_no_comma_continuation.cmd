-- In batch/file execution (including a script run directly, as here), a
-- single-line IF's THEN-clause chains into an ELSEIF on the following
-- physical line with no continuation comma needed at all: the whole file is
-- one continuous token stream from the start, so Parse_If_Statement's
-- ELSEIF/ELSE lookahead already reaches across the line break. This is a
-- different execution mode from the interactive REPL (see
-- repl_if_elseif_no_continuation_error.cmd), which submits and executes each
-- line as it is typed and therefore does need the continuation comma.
LET inlrn=0
LET intst=1
RUN
if inlrn then let sample$="Learn"
elseif intst then let sample$="Test"
run
print sample$
run
quit
