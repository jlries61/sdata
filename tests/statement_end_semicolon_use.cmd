-- Option A (semicolon cleanup): a stray ";" after a bare USE (the stray ';' is now reported as a missing filename) must stay a syntax error.
USE ;
QUIT
