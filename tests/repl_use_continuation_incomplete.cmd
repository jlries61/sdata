-- sdata#90 regression guard: this is the exact scenario that regressed
-- during this fix's own development -- a comma-delimited list (USE's
-- dataset list) left dangling with nothing following the continuation
-- comma must still make the REPL prompt "..>" and wait, not silently
-- treat the statement as complete (and, worse, not surface a raw parse
-- error instead of the graceful prompt). No QUIT below is deliberate:
-- stdin simply runs out while still awaiting the continuation.
USE "tests/data/freq.csv",
