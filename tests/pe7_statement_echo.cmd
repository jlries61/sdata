-- PE-7 (design.md sec6.3, ADR-061): interactive-mode statements must be
-- echoed to screen even under piped/non-tty stdin, where the terminal's own
-- canonical-mode echo does not apply. This is the audit's own repro
-- (part-e-io-operators-implementation-notes.md), pinned as a direct
-- regression guard.
USE MOCK
LET Z = 5
PRINT Z
RUN
QUIT
