-- ADR-060: a per-dataset spec option missing its '=' must fail cleanly.
-- Representative of the shared USE/SAVE spec-option parser's ~15 error
-- sites (KEEP/DROP/RENAME/IN/IF/HEADER/FMT/CHARSET/NSCAN/SKIP/MAXROWS/
-- DECIMALS/unknown-option/EOF/unexpected-token) -- not individually tested,
-- all converted the same mechanical way.
USE "tests/data/charset_ascii_clean.csv" (KEEP NAME$)
QUIT
