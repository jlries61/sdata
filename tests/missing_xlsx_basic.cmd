-- USE /MISSING= now recognizes declared tokens on OOXML input too
-- (sdata-core ADR-0026, amended), not just CSV.  Identical setup to
-- missing_ods_basic.cmd; the two readers are structurally the same code
-- and must behave identically.
USE "tests/data/missing_declared.csv" / MISSING="NA"
SAVE "tests/data/missing_declared_gen.xlsx" / MISSING="NA"
RUN
USE "tests/data/missing_declared_gen.xlsx" / MISSING="NA"
PRINT ID VALUE
RUN
SYSTEM "rm -f tests/data/missing_declared_gen.xlsx"
END
