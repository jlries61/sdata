-- Tests for functions added in v0.6.2:
-- PI, TIMER, TRUNCATE, LBOUND, UBOUND, INDEX, MATCH, MAXLEN, MAXLVL,
-- MAXINT, MININT, MAXNUM, MINNUM, RAD/RADIAN, LTW

-- PI
PRINT PI()

-- TRUNCATE: toward zero, no rounding
PRINT TRUNCATE(3.14159, 2)
PRINT TRUNCATE(-3.14159, 2)
PRINT TRUNCATE(3.9, 0)
PRINT TRUNCATE(-3.9, 0)

-- RAD / RADIAN: degrees to radians
PRINT RAD(180)
PRINT RADIAN(90)
PRINT RAD(0)

-- Integer-limit constants
PRINT MAXINT()
PRINT MININT()

-- Float-limit constants (relational: avoid E-notation literals)
PRINT (MAXNUM() > MAXINT())
PRINT (MINNUM() > 0)
PRINT (MINNUM() < 1)

-- TIMER: non-negative
PRINT (TIMER() >= 0)

-- MAXLVL: implementation constant
PRINT MAXLVL()

-- MAXLEN: 0 means unlimited (default, no --clen)
PRINT MAXLEN("x")

-- INDEX: find B$ in A$, 1-based or 0
PRINT INDEX("Hello World", "World")
PRINT INDEX("Hello World", "xyz")
PRINT INDEX("Hello World", "")

-- MATCH: find B$ in A$ starting from position X%
PRINT MATCH("Hello World", "World", 1)
PRINT MATCH("Hello World", "World", 8)
PRINT MATCH("abcabc", "abc", 2)

-- LBOUND / UBOUND: custom and default subscript ranges
DIM A(3 TO 7)
DIM B(5)
PRINT LBOUND(A)
PRINT UBOUND(A)
PRINT LBOUND(B)
PRINT UBOUND(B)

-- LTW: Lambert W principal branch; LTW(e) = 1 because 1*e^1 = e
PRINT LTW(0)
PRINT LTW(1)
PRINT LTW(2.71828)

RUN
QUIT
