-- SAVE /MISSING= is overridable per-target, like /DECIMALS=: target A
-- writes the token, target B (no override) keeps writing blank.  Re-reading
-- target A without declaring /MISSING= confirms the token was actually
-- written as text (the column retypes to X$, same as any unrecognized
-- string) -- target B stays numeric and missing, matching the source.
USE "tests/data/missing_first.csv"
SAVE "tests/data/missing_pt_a.csv" (MISSING="NA"), "tests/data/missing_pt_b.csv"
RUN
USE "tests/data/missing_pt_a.csv"
PRINT X$ Y
RUN
USE "tests/data/missing_pt_b.csv"
PRINT X Y
RUN
SYSTEM "rm -f tests/data/missing_pt_a.csv tests/data/missing_pt_b.csv"
END
