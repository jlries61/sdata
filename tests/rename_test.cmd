-- Test RENAME command

-- Basic single rename
USE "tests/data/data.csv"
RENAME ID=IDENT
NAMES
RUN

-- Multiple renames in one statement
NEW
USE "tests/data/data.csv"
RENAME ID=NUM, NAME$=LABEL
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
