-- ADR-060: DIM bounds using anything other than TO or ')' must fail
-- cleanly.
DIM V(1 XX 3)
QUIT
