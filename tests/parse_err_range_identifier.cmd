-- ADR-060: a KEEP/DROP variable-range missing its end identifier must fail
-- cleanly, not silently continue with a malformed range entry.
KEEP A-
QUIT
