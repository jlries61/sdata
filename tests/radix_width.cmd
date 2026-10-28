-- F26 (2026-10-19 stress test) regression: HEX$/OCT$/BIN$ take the optional
-- width argument design.md documents; the digits are zero-padded on the left.
REPEAT 1
LET A$ = HEX$(255)
LET B$ = HEX$(255, 4)
LET C$ = HEX$(255, 1)
LET D$ = OCT$(8, 5)
LET E$ = BIN$(5, 8)
LET F$ = BIN$(5, 0)
PRINT A$, B$, C$, D$, E$, F$
RUN
REPEAT 1
LET G$ = HEX$(1, 300)
RUN
QUIT
