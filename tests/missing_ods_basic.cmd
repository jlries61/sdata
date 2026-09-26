-- USE /MISSING= now recognizes declared tokens on ODF input too (sdata-core
-- ADR-0026, amended), not just CSV.  Build an .ods from the same fixture the
-- CSV MISSING tests use (read-declaring "NA" so VALUE stays numeric and the
-- write side re-emits the missing cell as literal "NA" text) and confirm
-- reading it back with the token declared again reproduces CSV's exact
-- behavior: recognized as missing, one summary note, no coercion warning.
USE "tests/data/missing_declared.csv" / MISSING="NA"
SAVE "tests/data/missing_declared_gen.ods" / MISSING="NA"
RUN
USE "tests/data/missing_declared_gen.ods" / MISSING="NA"
PRINT ID VALUE
RUN
SYSTEM "rm -f tests/data/missing_declared_gen.ods"
END
