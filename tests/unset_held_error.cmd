-- UNSET on a currently-held variable is rejected outright, rather than
-- silently no-op'ing (Get() reads PDV_Vec before Temp_Symbols, so deleting
-- only the Temp_Symbols mirror while still held had no visible effect in
-- practice) or corrupting the HOLD/UNHOLD mirroring mechanism.
NEW
USE MOCK
HOLD SUMVAL
LET SUMVAL = 1
UNSET SUMVAL
PRINT SUMVAL
RUN
QUIT
