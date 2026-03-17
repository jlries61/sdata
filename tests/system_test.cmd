-- Test for System Command and Shell Function
SYSTEM "echo 'System Command OK'"
LET X = SHELL("echo 'Shell Function OK'")
PRINT "Exit Code:" X
RUN
QUIT
