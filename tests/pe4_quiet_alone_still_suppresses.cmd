-- PE-4 / ADR-061 (sdata-core ADR-0022): control case for the ECHO-undoes--q
-- fix -- -q alone (no ECHO ON) must still fully suppress console output,
-- confirming the unification didn't accidentally make -q a no-op.
USE MOCK
LET X = 1
PRINT "hello world"
RUN
