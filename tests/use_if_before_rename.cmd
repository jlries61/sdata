-- IF= evaluates against a spec's ORIGINAL column name, before that same
-- spec's own RENAME= renames it (ADR-074/sdata#92). X is renamed to W;
-- IF= still filters on X, not W -- if it were evaluated post-rename, the
-- reference to X would be an undefined-variable error instead.
USE "tests/data/merge_a_13.csv" (IF=X>=20, RENAME=(X=W))
PRINT ID W
RUN
NEW
END
