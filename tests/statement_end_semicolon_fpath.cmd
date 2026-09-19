-- Option A (semicolon cleanup): a stray ";" after FPATH (it must not silently set the path to ';') must stay a syntax error.
FPATH ;
QUIT
