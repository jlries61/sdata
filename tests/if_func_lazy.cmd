REM Test IF() function with lazy evaluation.
REM The non-taken branch must not be evaluated -- LOG(-1) would raise a
REM domain error if evaluated eagerly, so this test passes only when the
REM fix is in place.
REPEAT 3
   LET I# = RECNO
RUN
LET Y = IF(I# > 0, I#, LOG(-1))
PRINT Y
RUN
END
