-- Gate MINOR-2: a stray ";" after a complete statement is named in the error (it used to
-- print unexpected "" because a semicolon token carries no text of its own).
LET X = 1 ; PRINT X
QUIT
