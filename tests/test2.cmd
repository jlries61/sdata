REM Testing line continuation and ranges
USE "input.csv",
    -- comment-like line continuation (though REM is for full lines)
    "ignored" 
KEEP A:Z,
     VAR1-VAR100
DROP TEMP1, TEMP2
LET X = 1
PRINT X
RUN
END
