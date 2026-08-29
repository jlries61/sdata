-- ECHO with a garbage argument must fail, not silently disable echo.
-- Previously fell through to the else branch and was treated as OFF with
-- no error at all -- confirmed empirically before this fix.
ECHO BOGUS
PRINT "should never run"
RUN
QUIT
