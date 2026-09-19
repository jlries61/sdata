-- Option A (semicolon cleanup): a stray ";" after a bare SAVE (the stray ';' is now reported as a missing filename) must stay a syntax error.
SAVE ;
QUIT
