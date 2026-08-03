-- Issue #70 / ADR-055: SORT placed between REPEAT n and its matching RUN
-- (formerly rejected outright by ADR-051/#66) now triggers an implicit RUN
-- first. The REPEAT body here is empty (no LET/SET queued), so the implicit
-- RUN creates 6 records with zero columns; SORT X then correctly hits
-- ADR-052's unconditional undefined-variable check (X was never a real
-- column) rather than silently no-op'ing -- proving the from-scratch
-- empty-REPEAT-body edge case still resolves to a clean error, not a
-- silent success.
NEW
REPEAT 6
SORT X
QUIT
