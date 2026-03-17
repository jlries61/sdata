-- Test SUBMIT recursion detection (should fail with error, not loop)
SUBMIT "tests/data/submit_recurse_a.cmd"
RUN
QUIT
