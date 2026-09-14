-- REPL-mode companion to if_single_line_trailing_comma.cmd: the trailing
-- comma triggers the "..>" continuation prompt (design.md sec5.4), buffering
-- the ELSEIF line together with the THEN-clause line before parsing -- so the
-- merged statement chains normally, exactly as it would if typed on one line
-- (or in a script file, where this always works with no comma needed).
LET inlrn=1
RUN
if inlrn then let sample$="Learn",
  elseif 0 then let sample$="Test"
run
quit
