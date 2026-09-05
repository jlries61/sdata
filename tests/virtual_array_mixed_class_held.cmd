-- ADR-0023 (sdata-core issue #118): a HELD permanent variable's Temp_Symbols
-- carry-over mirror (Reset_PDV_Non_Held) must not be misread as a genuine
-- temporary when it's a virtual-array constituent -- LET through array
-- syntax must keep succeeding across records, exactly as bare LET TOTAL
-- already does today (see hold_test.cmd). SData_Core.Variables.
-- Element_Is_Temporary excludes Is_Held constituents from "genuine
-- temporary" for this reason.
REPEAT 2
HOLD TOTAL
IF MISSING(TOTAL) THEN LET TOTAL = 0
LET Q = 0
ARRAY V TOTAL Q
LET V(1) = V(1) + RECNO()
PRINT V(1) V(2)
RUN
QUIT
