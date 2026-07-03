-- Issue #40: a RUN must not wipe earlier console output from an OUTPUT-redirected
-- file. OUTPUT is an immediate command; it was being re-executed once per record
-- during the data step, and each re-execution truncates the redirect file
-- (Open_Output uses Create), leaving only the final "RUN complete" line.
-- Here OUTPUT is entered AFTER USE so the fix (not the incidental Step_Start
-- change) is what must carry it. The file is read back via SYSTEM cat.
USE "mock"
OUTPUT "tests/output40_capture.dat"
DISPLAY
RUN
OUTPUT
SYSTEM "echo === captured file ==="
SYSTEM "cat tests/output40_capture.dat"
SYSTEM "rm -f tests/output40_capture.dat"
QUIT
