-- EOF() must be true only on the last record of a REPEAT n data step, not
-- every record.  Row_Count only reflects rows already flushed to the
-- table; during REPEAT, Process_One_Record sets the current record index
-- and runs the record's own body (where EOF() may be called) *before*
-- flushing/adding that record's row, so Row_Count lags the current record
-- index by exactly one throughout the body -- comparing Current_Record
-- against the still-growing Row_Count made EOF true on every record.
-- sdata_core-evaluator-nav_fns.adb's Handle_EOF now uses
-- Config.Runtime.Repeat_Count (known up front, unlike Row_Count) as the
-- total when a REPEAT is active. BOF is unaffected: it doesn't need a
-- total, only whether the current record is the first.
NEW
REPEAT 3
LET B = BOF()
LET E = EOF()
PRINT "REC:" RECNO() "BOF:" B "EOF:" E
RUN

-- USE-loaded tables must be unaffected: the whole file is read into the
-- table before the data step runs, so Row_Count is already the final
-- total from the start.
NEW
USE "mock"
LET B2 = BOF()
LET E2 = EOF()
PRINT "REC:" RECNO() "BOF:" B2 "EOF:" E2
RUN

-- A single-record REPEAT is simultaneously the first and last record.
NEW
REPEAT 1
LET E3 = EOF()
PRINT "single-record EOF:" E3
RUN

QUIT
