-- ADR-062/issue #76: DIM's array-bound expressions previously evaluated
-- an unknown function silently (Val_Missing coerced into a bound-parsing
-- error unrelated to the real mistake). Now raises the clean "unknown
-- function" error at DIM's own statement, before any evaluation.
DIM A(BOGUSFUNC(1))
QUIT
