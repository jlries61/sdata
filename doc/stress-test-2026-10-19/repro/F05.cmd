REPEAT 1
LET V = ROUND(1,400)
PRINT V
RUN
REM expect a number or an error; actual: NaN (spec says NaN is never exposed)
