-- sdata#90: USE's comma-delimited dataset list must also continue
-- correctly across the REPL's "..>" prompt boundary, the same as it
-- already did (via the comma being invisible) for PRINT's space-separated
-- list in repl_continuation.cmd -- confirming the fix's call-boundary
-- design (Just_Emitted_Continuation_Comma) doesn't just work in batch mode.
USE "tests/data/freq.csv",
"tests/data/freq.csv" /APPEND
NAMES
QUIT
