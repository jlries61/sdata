-- design.md sec6.3, ADR-061: interactive-mode statements must be echoed to
-- screen even under piped/non-tty stdin, where the terminal's own
-- canonical-mode echo does not apply. Pinned as a direct regression guard.
USE MOCK
LET Z = 5
PRINT Z
RUN
QUIT
