-- NOTE (ADR-059): bare NOTE with no arguments is a Script_Error -- unlike
-- PRINT's bare form, there is no "current record" for NOTE to print
-- permanent variables of (it doesn't accept them at all).
NOTE
QUIT
