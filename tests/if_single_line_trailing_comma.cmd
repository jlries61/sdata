-- A trailing comma after a single-line IF's THEN-clause is a continuation
-- marker (design.md sec5.4; ADR-072), so the ELSEIF on the next line remains
-- part of the same IF statement, exactly as it would if typed on one line --
-- this matters in batch/file execution too (where ELSEIF already chains with
-- no comma needed, since the whole file is one token stream), but is essential
-- in the REPL, which otherwise submits and executes the THEN-clause before
-- ELSEIF is even typed. No error; the ELSEIF branch is skipped since inlrn is
-- true, so sample$ is set by the THEN-clause.
LET inlrn=1
LET intst=0
RUN
if inlrn then let sample$="Learn",
  elseif intst then let sample$="Test"
run
print sample$
run
quit
