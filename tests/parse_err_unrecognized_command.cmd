-- ADR-060: an unrecognized command name must fail the whole script, not
-- silently continue running the rest of it -- the cleanest single repro
-- of the whole bug class this workstream fixes. Confirmed via
-- .ssd/audits before this fix: USE MOCK still ran and RUN still
-- completed (exit 0) despite this exact error printing. No prior test
-- covered this at all despite it being the audit's own second repro.
USE MOCK
BOGUSCOMMAND
RUN
