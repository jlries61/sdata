USE "F36_range.csv"
LET S = SUM(X1:X3)
RUN
DISPLAY
STATS X1:X3
REM S should be 6 and 18; STATS should list X1 X2 X3
