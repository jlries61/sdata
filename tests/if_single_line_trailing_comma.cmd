-- A trailing comma after a single-line IF's THEN-clause does not extend the
-- IF to a following ELSEIF the way the block form does (see the "single-line
-- IF is complete as typed" note added to design.md/HELP/the man page) -- but
-- it also must not itself raise a spurious "Unrecognized command ','" error;
-- the only error should be for ELSEIF itself (a new, unrelated statement, not
-- a continuation of the single-line IF).
LET inlrn=1
LET intst=0
RUN
if inlrn then let sample$="Learn",
  elseif intst then let sample$="Test"
run
print sample$
run
quit
