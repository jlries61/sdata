-- String relational operators: <, >, <=, >=, <>
PRINT ("apple" < "banana")
PRINT ("zebra" > "ant")
PRINT ("cat" <= "cat")
PRINT ("cat" >= "dog")
PRINT ("abc" <> "ABC")
RUN

-- MISSING and NMISS treat empty string as missing
LET E$ = ""
PRINT "MISSING empty string:" MISSING(E$)
PRINT "NMISS with empties:" NMISS("hello", "", "world", "")
RUN
END
