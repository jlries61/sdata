-- A KEEP that doesn't name either IN= variable must not error: Execute_KEEP
-- already drops fromA/fromB as unlisted columns before the auto-drop pass
-- runs, so the auto-drop pass must silently no-op on a name Execute_KEEP
-- already removed rather than raising "does not exist" the way a real
-- user-issued DROP would for a genuinely missing column.
USE "tests/data/merge_a.csv" (IN=fromA), "tests/data/merge_b.csv" (IN=fromB) /APPEND
KEEP ID X Y
RUN
NAMES
QUIT
