USE "F25_utf8.csv"
LET L$ = LCASE$(NAME$)
LET U$ = UCASE$(NAME$)
LET N = LEN(NAME$)
SAVE "F25_out.csv"
RUN
REM F25_out.csv is not valid UTF-8
