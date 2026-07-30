-- Regression test: deleting every record from a SPILLED dataset hits
-- Commit_Output_Table's "truncate" branch (Output_Table_Row_Count = 0),
-- which drops both the data/output_data tables outright. Under the EAV
-- schema (ADR-0011) this must also drop the data_cols/output_data_cols
-- registry tables and reset the in-memory col_id registries -- otherwise a
-- later spill of a fresh table (same or a differently-shaped column set)
-- could see a stale UNIQUE constraint violation or silently reuse a col_id
-- for the wrong column name. Force a spill via -m (see .flags), delete
-- every record, then USE + spill a SECOND, differently-named dataset in
-- the same session to prove the registries actually reset.
SYSTEM "seq 1 50 | sed 's/^/c/' | paste -sd, - > tests/data/spill_delete_a.csv && seq 1 50 | paste -sd, - >> tests/data/spill_delete_a.csv"
USE "tests/data/spill_delete_a.csv"
DELETE
RUN

SYSTEM "seq 1 50 | sed 's/^/d/' | paste -sd, - > tests/data/spill_delete_b.csv && seq 51 100 | paste -sd, - >> tests/data/spill_delete_b.csv"
USE "tests/data/spill_delete_b.csv"
PRINT "d1=" D1 "d50=" D50
RUN

SYSTEM "rm -f tests/data/spill_delete_a.csv tests/data/spill_delete_b.csv"
QUIT
