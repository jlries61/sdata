-- Issue #71 / systems-designer Finding 1: before the .n literal existed,
-- MIN/MAX could never see a NaN as the first value in a BY group (NaN was
-- unreachable as a stored value). Compute_Stats_Pass seeds its running
-- Min_V/Max_V from the first non-missing value and updates only via a
-- plain comparison, which is always False against NaN under IEEE 754 --
-- so a NaN-first group used to freeze MIN()/MAX() at NaN silently. This
-- must now raise the same domain error SUM/MEAN already give, not return
-- a silently-wrong result.
NEW
REPEAT 2
  LET G = 1
  IF RECNO() = 1 THEN LET X = .n
  IF RECNO() = 2 THEN LET X = 5
RUN
BY G
AGGREGATE LO=MIN(X)
QUIT
