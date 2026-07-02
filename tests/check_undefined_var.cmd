-- Entry-time check: a bare identifier that names nothing defined is rejected
-- before the data step.  NOSUCHVAR is not a column, variable, array, reserved
-- pseudo-name, or introduced anywhere in the block, so the analyzer must raise
-- pre-RUN and no "RUN complete" line may appear.
USE MOCK
LET X = NOSUCHVAR + 1
RUN
