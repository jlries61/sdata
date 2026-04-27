-- Tests for OPTIONS command (v0.6.2)

-- 1. CSVDLM: write tab-delimited, read back — IDs should print 1,2,3
OPTIONS CSVDLM "	"
USE MOCK
SAVE "/tmp/sdata_opt_tab.csv"
RUN
USE "/tmp/sdata_opt_tab.csv"
PRINT ID
RUN

-- 2. HEADER NO write: file contains no header row (use comma delimiter)
OPTIONS CSVDLM ","
OPTIONS HEADER NO
USE MOCK
SAVE "/tmp/sdata_opt_nohdr.csv"
RUN

-- 3. HEADER NO read: first column COL1 should contain 1,2,3
USE "/tmp/sdata_opt_nohdr.csv"
PRINT COL1
RUN

-- 4. SAVEOVERWRT NO: error printed; RUN still completes
OPTIONS HEADER YES
OPTIONS SAVEOVERWRT NO
USE MOCK
SAVE "/tmp/sdata_opt_nohdr.csv"
RUN

-- 5. MAXINTAB / MAXTEMPMEM: no error
OPTIONS MAXINTAB 0
OPTIONS MAXTEMPMEM 0

QUIT
