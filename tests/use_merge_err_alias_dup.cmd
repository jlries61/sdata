-- Error test: two USE dataset specs with the same AS alias.
-- Verifies the executor emits: duplicate USE alias: X
USE "tests/data/merge_a.csv" AS X, "tests/data/merge_b.csv" AS X /BY=ID
NEW
END
