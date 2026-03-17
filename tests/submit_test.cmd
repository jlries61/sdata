-- Test SUBMIT command
-- The submitted script just prints a message and defines a variable
SUBMIT "tests/data/submit_sub.cmd"
PRINT "Back in main script"
RUN
QUIT
