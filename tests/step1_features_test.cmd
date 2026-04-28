-- Step 1 features: E-notation, single-quote strings, HEX, SEG$, FRAC, OUTPUT flags
-- E-notation literals
PRINT "1.5E3:"  1.5E3
PRINT "2.0E-2:" 2.0E-2
PRINT "1.5E+2:" 1.5E+2
PRINT "3E2:"    3E2
-- Single-quote string literals
LET S$ = 'hello world'
PRINT "SQ:" S$
PRINT "SQ-LEN:" LEN(S$)
-- HEX string-to-integer
PRINT "HEX(FF):"  HEX("FF")
PRINT "HEX(1a):"  HEX("1a")
PRINT "HEX(0):"   HEX("0")
-- SEG$ substring
PRINT "SEG1:" SEG$("Hello World", 7, 5)
PRINT "SEG2:" SEG$("Hello", 0, 3)
PRINT "SEG3:" SEG$("Hello", 1, 3)
-- FRAC alias for FP
PRINT "FRAC1:" FRAC(3.75)
PRINT "FRAC2:" FRAC(-2.3)
RUN
-- OUTPUT /FMT= and /CHARSET= parse without error
OUTPUT /FMT=LF
OUTPUT /CHARSET=UTF8
OUTPUT
QUIT
