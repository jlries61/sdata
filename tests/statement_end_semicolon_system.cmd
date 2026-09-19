-- Option A (semicolon cleanup): a stray ";" after SYSTEM (it is what stops the shell from being handed ';' as a command) must stay a syntax error.
SYSTEM ;
QUIT
