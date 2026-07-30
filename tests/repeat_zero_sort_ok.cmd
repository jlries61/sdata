-- issue #66 boundary case: REPEAT 0 is the documented "cancel any active
-- REPEAT" form (SData_Core.Commands.Execute_REPEAT clears Repeat_Active when
-- Count = 0) -- it does not open a data-generation window, so a SORT right
-- after it must not be rejected by the new guard (it is a pre-existing,
-- documented no-op on the resulting empty table, not a new error).
NEW
REPEAT 0
SORT X
QUIT
