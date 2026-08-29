-- A plausible wrong-type guess (a bare number) must also fail, not
-- silently disable echo. Confirms the fix rejects any non-ON/OFF token,
-- not just alphabetic garbage.
ECHO 1
PRINT "should never run"
RUN
QUIT
