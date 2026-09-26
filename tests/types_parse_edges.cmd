-- R-C edge cases for /TYPES= parsing, pinned so a future refactor of the
-- two-syntax normalization cannot quietly change them (02-systems-designer
-- section 4).  Baseline header is CODE$,VAL -- untouched it loads as
-- "CODE$ VAL".
--
-- 1. Whitespace around entries is trimmed.
USE "tests/data/types_demote.csv" / TYPES="  CODE ,  VAL%  "
NAMES
-- 2. Matching is case-insensitive: lowercase "code" finds column CODE$
--    and demotes it (the $ is stripped).
USE "tests/data/types_demote.csv" / TYPES="code"
NAMES
-- 3. A comma between keyword-form entries is tolerated, matching
--    Parse_Rename_List's own behavior inside its parentheses.
USE "tests/data/types_demote.csv" / TYPES=(CODE=NUM,VAL=INT)
NAMES
-- 4. Keyword names are case-insensitive too.
USE "tests/data/types_demote.csv" / TYPES=(code=char)
NAMES
END
