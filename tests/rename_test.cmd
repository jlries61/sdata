-- Test RENAME command

-- Basic single rename
USE "tests/data/data.csv"
RENAME ID=IDENT
NAMES
RUN

-- Multiple renames in one statement (a character name must stay character,
-- design.md section 7.1 -- the former NAME$=LABEL was the F17 defect)
NEW
USE "tests/data/data.csv"
RENAME ID=NUM, NAME$=LABEL$
NAMES
RUN

-- Rename then use new name in LET
NEW
USE "tests/data/data.csv"
RENAME NAME$=PERSON$
LET GREETING$ = "Hello " + PERSON$
PRINT GREETING$
RUN

QUIT
