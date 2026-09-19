-- Option A (semicolon cleanup): a stray ";" after SUBMIT (it must not go looking for a file named ';') must stay a syntax error.
SUBMIT ;
QUIT
