-- Bare ECHO with no argument at all must fail, not silently disable echo.
-- The statement-terminating newline token was previously consumed and
-- compared against "ON", silently failing the comparison and falling
-- through to OFF with no error.
ECHO
PRINT "should never run"
RUN
QUIT
