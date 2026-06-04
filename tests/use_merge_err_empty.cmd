-- Error test: USE with slash-options but no datasets.
-- Verifies the parser emits: USE requires at least one dataset.
USE /BY=ID
QUIT
