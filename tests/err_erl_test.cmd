-- Test ERR() and ERL() functions with -k (--continue-on-error).
-- ERR() returns 1 after a caught error, 0 before any error.
-- ERL() returns the record number where the last error occurred.
DIGITS 5

-- First data step: trigger division-by-zero on record 2 of 3.
REPEAT 3
  LET Z = 0
  IF RECNO = 2 THEN LET X = 1 / Z
RUN

-- Second data step: print ERR and ERL (non-zero because first step had an error).
REPEAT 1
  PRINT "ERR after error:" ERR()
  PRINT "ERL (record of error):" ERL()
RUN

QUIT
