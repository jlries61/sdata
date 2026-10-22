-- F19 (2026-10-19 stress test) regression: WIF(p, scale, shape) is the
-- inverse of WCF(x, scale, shape).  Includes a shape < 1, where the old
-- bisection bracket (10 * scale) was too small.
DIGITS 10
REPEAT 1
LET A = WIF(0.5, 2, 3)
LET B = WCF(A, 2, 3)
LET C = WIF(0.99, 3, 0.2)
LET D = WCF(C, 3, 0.2)
PRINT A B C D
RUN
END
