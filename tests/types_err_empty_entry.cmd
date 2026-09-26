-- An empty entry in the /TYPES= list is an error, not a silently skipped
-- element -- the same one-rule strictness as the duplicate-name check.
USE "tests/data/types_demote.csv" / TYPES="CODE,,VAL"
END
