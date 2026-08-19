-- 2026-08-13 re-audit PC-4: DROP cannot remove a temporary array any more
-- than it can remove a temporary scalar (design.md's DROP row: "A DROP
-- statement that lists a variable that does not exist as a permanent
-- (table column) variable -- including a temporary (SET) variable, which
-- DROP cannot remove; use UNSET instead -- shall fail with an error
-- message"). A temporary real array's elements live in the temporary
-- symbol table, never as table columns -- this is the array-shaped
-- instance of that same documented rule, not a new gap for PC-4 to close.
DIM Z(1 TO 2) /TEMP
SET Z(1) = 5
SET Z(2) = 15
DROP Z
RUN
QUIT
