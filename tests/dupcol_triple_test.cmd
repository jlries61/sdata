-- ADR-0028 (sdata-core) regression: a column name repeated 3+ times (not
-- just once) must warn for each duplicate occurrence and must NOT crash.
-- This is the one case the Name_Vecs->Name_Sets fix could get wrong: a
-- hashed Set.Insert on an already-present element raises Constraint_Error,
-- unlike the old Vector.Append, which silently duplicated harmlessly -- so
-- Warn_If_Duplicate_Name must call Insert only on the non-duplicate branch.
-- Two occurrences alone (see dupcol_test.cmd) cannot distinguish "insert
-- unconditionally" from "insert only when new"; a third occurrence of the
-- same name is the one that would crash if Insert were ever unconditional.
USE "tests/data/dupcol_triple.csv"
RUN
QUIT
