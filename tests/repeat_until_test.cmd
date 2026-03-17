-- Test REPEAT/UNTIL loop
LET I = 1
REPEAT
  PRINT "I:" I
  LET I = I + 1
UNTIL I > 3
RUN

-- REPEAT/UNTIL executes body at least once even when condition is true initially
LET J = 10
REPEAT
  PRINT "J (should print once):" J
  LET J = J + 1
UNTIL J > 5
RUN
QUIT
