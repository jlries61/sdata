-- USE MOCK (IF=...) -- confirms mock-generated rows are filtered
-- identically to file-loaded rows (ADR-074/sdata#92). MOCK generates
-- IDs 1,2,3 (Alice/Bob/Charlie); IF=ID>1 keeps Bob and Charlie.
USE MOCK (IF=ID>1)
PRINT ID NAME$ SALARY
RUN
NEW
END
