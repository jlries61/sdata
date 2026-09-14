-- REPL-mode companion to if_single_line_trailing_comma.cmd: the trailing
-- comma still triggers the "..>" continuation prompt (design.md sec5.4
-- applies unconditionally), even though the resulting merged statement then
-- fails for the same, separate, expected reason (ELSEIF cannot follow a
-- single-line IF).
LET inlrn=1
RUN
if inlrn then let sample$="Learn",
  elseif 0 then let sample$="Test"
run
quit
