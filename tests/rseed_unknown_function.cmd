-- ADR-062/issue #76: RSEED's seed expression previously fell through to a
-- confusing secondary error ("Cannot convert VAL_MISSING to Real") when
-- the seed expression called an unknown function, instead of the clean
-- "unknown function" error PRINT gives for the identical mistake.
RSEED BOGUSFUNC(1)
QUIT
