-- Test DO/UNTIL loop (issue #63 / ADR-054: renamed from REPEAT/UNTIL to
-- resolve the keyword overload with the REPEAT n data-step command).
LET I = 1
DO
  PRINT "I:" I
  LET I = I + 1
UNTIL I > 3
RUN

-- DO/UNTIL executes body at least once even when condition is true initially
LET J = 10
DO
  PRINT "J (should print once):" J
  LET J = J + 1
UNTIL J > 5
RUN
QUIT
