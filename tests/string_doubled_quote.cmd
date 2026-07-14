-- Issue #52: a doubled quote ("") inside a double-quoted string must produce
-- a single literal " and continue scanning, at ANY position (middle, start,
-- end, whole string), while a lone "" stays the empty string.
PRINT "a""b"
PRINT """x"
PRINT "y"""
PRINT """"
PRINT "he said ""hi"" ok"
PRINT "plain"
PRINT ""
RUN
QUIT
