-- Test OUTPUT command: redirect console output to a file
OUTPUT "tests/output_test_capture.dat"
PRINT "Line written to file and stdout"
LET X = 42
PRINT "X =" X
OUTPUT
RUN
QUIT
