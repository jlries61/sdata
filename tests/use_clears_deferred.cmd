-- A LET queued before USE must be cancelled by USE (design.md:960).
-- MARKER must NOT appear as a column after RUN.
LET MARKER = 1
USE MOCK
NAMES
RUN
