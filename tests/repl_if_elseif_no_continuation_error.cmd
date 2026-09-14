-- Pins down the genuine REPL-only restriction (originally reported and
-- documented as doc-only, "1 for now"): with no continuation comma, the
-- REPL judges a single-line IF's THEN-clause complete the moment it is
-- typed and submits it for execution immediately -- ELSEIF on the next
-- line has not been typed yet at that point, so it is parsed as a new,
-- unrelated top-level statement and rejected. Contrast with
-- if_elseif_batch_no_comma_continuation.cmd (batch mode, same statement
-- text, no comma, succeeds) and repl_if_single_line_trailing_comma.cmd
-- (REPL mode, comma added, succeeds).
LET inlrn=1
RUN
if inlrn then let sample$="Learn"
elseif 0 then let sample$="Test"
run
quit
