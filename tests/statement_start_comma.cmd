-- Gate MINOR-2 / ADR-080: a comma that begins a line (it does not end the previous one) is
-- not a statement separator and not a valid statement start; the error names it.
PRINT 1
, PRINT 2
QUIT
