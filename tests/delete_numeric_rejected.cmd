-- Issue #63 / ADR-054: DELETE no longer accepts the pre-rename DELETE
-- n[-m] program-buffer-editor spelling (that command is now REMOVE n[-m])
-- -- DELETE followed by a numeric argument must raise a clean,
-- migration-specific error.
DELETE 1
QUIT
