-- Issue #71 / ADR-057: .n constructs NaN as a usable sentinel value, but
-- the existing NaN-rejection guard (proven by inf_divide.cmd's 0.0/0.0)
-- must still trip the moment .n is used arithmetically -- the literal
-- does not weaken that guard, it only adds a way to construct the value.
DIGITS 5
REPEAT 1
  LET A = .n + 1
  PRINT A
  LET B = .n * 2
  PRINT B
RUN
QUIT
