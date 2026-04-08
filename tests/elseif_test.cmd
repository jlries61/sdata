-- Test ELSEIF chains (inline and block forms)

-- Block form: multi-level ELSEIF chain
REPEAT 5
IF RECNO() = 1 THEN
  PRINT "one"
ELSEIF RECNO() = 2 THEN
  PRINT "two"
ELSEIF RECNO() = 3 THEN
  PRINT "three"
ELSEIF RECNO() = 4 THEN
  PRINT "four"
ELSE
  PRINT "other"
END IF
RUN

-- Inline form: ELSEIF on a single line
NEW
REPEAT 3
IF RECNO() = 1 THEN PRINT "A" ELSEIF RECNO() = 2 THEN PRINT "B" ELSE PRINT "C"
RUN

-- ELSEIF with no trailing ELSE (falls through silently when no branch matches)
NEW
REPEAT 4
IF RECNO() = 1 THEN
  PRINT "first"
ELSEIF RECNO() = 2 THEN
  PRINT "second"
END IF
RUN

-- Nested IF inside ELSEIF branch
NEW
REPEAT 4
IF RECNO() = 1 THEN
  PRINT "low"
ELSEIF RECNO() <= 3 THEN
  IF RECNO() = 2 THEN
    PRINT "mid-low"
  ELSE
    PRINT "mid-high"
  END IF
ELSE
  PRINT "high"
END IF
RUN

QUIT
