-- Type mismatch in an expression (numeric + string) must raise Script_Error
LET X = 1 + "hello"
PRINT X
RUN
END
