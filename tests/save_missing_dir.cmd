-- Regression test for P14 (design-vs-implementation audit,
-- .ssd/audits/2026-08-03-design-vs-implementation/report.md): SAVE to a
-- non-existent target directory used to leak a raw Ada exception
-- (ADA.IO_EXCEPTIONS.NAME_ERROR: ...) instead of the clean, immediate error
-- design.md §4.3/§4.5 promise ("Data Integrity: ... shall immediately
-- verify: Target directory exists ... If conditions not met: statement
-- fails with an error message"). The error must surface at SAVE-statement
-- time, before RUN.
SAVE "/no/such/dir/out.csv"
QUIT
