-- ECHO ON/OFF must still work in any case (lowercase, mixed case), not
-- just the canonical uppercase form -- regression guard for the
-- echo-invalid-argument-error fix, which rewrote this argument check.
ECHO off
PRINT "should NOT appear (off, lowercase)"
RUN
ECHO On
PRINT "should appear (On, mixed case)"
RUN
ECHO OFF
PRINT "should NOT appear (OFF, uppercase)"
RUN
ECHO on
PRINT "should appear (on, lowercase)"
RUN
QUIT
