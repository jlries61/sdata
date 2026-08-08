-- Issue #71: the .i/.n literal lookahead must not change any pre-existing
-- dot-based syntax: leading-dot decimals (.5), the bare missing-value
-- literal (.), or a dot immediately followed by a longer identifier
-- (.info) -- all unchanged from before this feature.
REPEAT 1
  LET A = .5
  LET B = .
  PRINT A
  PRINT B
RUN
QUIT
