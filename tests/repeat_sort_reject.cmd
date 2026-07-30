-- issue #66: SORT placed between REPEAT n and its matching RUN must be
-- rejected, not silently no-op'd. Zero deferred statements are pending at
-- this point, so the existing AGGREGATE/TRANSPOSE/STATS-style
-- Pending_Deferred guard could not have caught this -- only a Repeat_Active
-- check does.
NEW
REPEAT 6
SORT X
QUIT
