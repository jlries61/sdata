-- Test ECHO command
ECHO OFF
PRINT "This should NOT appear on stdout"
RUN
ECHO ON
PRINT "This SHOULD appear on stdout"
RUN
QUIT
