-- Test block IF with ELSE and ELSEIF

-- Block IF with ELSE
REPEAT 3
IF RECNO() = 1 THEN
  PRINT "one"
ELSE
  PRINT "other"
END IF
RUN

-- Block IF with ELSEIF chain
REPEAT 4
IF RECNO() = 1 THEN
  PRINT "A"
ELSEIF RECNO() = 2 THEN
  PRINT "B"
ELSEIF RECNO() = 3 THEN
  PRINT "C"
ELSE
  PRINT "D"
END IF
RUN

-- Inline IF with ELSE (single statement each side)
REPEAT 3
IF RECNO() = 1 THEN PRINT "X" ELSE PRINT "Y"
RUN

QUIT
