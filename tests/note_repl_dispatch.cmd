-- NOTE (ADR-059): direct regression guard for the REPL dispatch trap this
-- codebase has repeatedly gotten wrong for other statements too (see
-- unset_immediate_repl.cmd) -- a bare NOTE must fire immediately when
-- typed interactively, not be
-- silently queued as if Deferred. Batch mode's own dispatch logic (an
-- exclusion list, not an inclusion list) would not have caught this class
-- of bug; only a real REPL-mode test does.
SET X = 7
RUN
NOTE X
QUIT
