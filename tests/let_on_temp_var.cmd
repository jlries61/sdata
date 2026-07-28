-- Issue #56: LET on an existing genuine temporary variable must fail loudly
-- (hard error, exit 1) instead of silently promoting it to a permanent
-- table column.
SET PROMOTED = 1
LET PROMOTED = PROMOTED + 9
RUN
