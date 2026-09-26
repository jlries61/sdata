-- The keyword form is an alias for the suffix form: both normalize to one
-- canonical representation in the parser, so they must produce identical
-- results (ADR-084).  Compare this output against types_use_basic.out.
USE "tests/data/missing_declared.csv" / TYPES=(VALUE=NUM)
NAMES
PRINT ID VALUE
RUN
END
