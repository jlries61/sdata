-- sdata-core ADR-0012: DIM may not redefine an existing
-- scalar variable as an array -- design.md sec3.5: "Existing scalar
-- variables may not be redefined as arrays unless first deleted."
LET S = 42
RUN
DIM S(1 TO 3)
RUN
QUIT
