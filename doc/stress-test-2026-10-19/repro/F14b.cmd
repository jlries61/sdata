USE "F14_cancel.csv"
STATS X /STATS=N MEAN VAR
REM true variance is ~0.083; sdata reports a wildly wrong value (here +1968; on other samples it is negative)
REPEAT 1
LET A = VAR(1000000000.1, 1000000000.2, 1000000000.3)
PRINT A
RUN
