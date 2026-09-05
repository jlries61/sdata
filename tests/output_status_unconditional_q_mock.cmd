-- sdata#81 / ADR-065: design.md sec6.1 says the OUTPUT-file transcript of
-- console output is unconditional even under -q (only the stdout copy is
-- suppressed). "Generating mock data...", "Dataset saved: ...", and "RUN
-- complete. ..." used to be dropped from the OUTPUT file too, because the
-- code gated the whole Put_Line call on Is_Local_Echo instead of letting
-- Put_Line's own internal gating handle stdout suppression. OUTPUT is
-- entered before USE so these messages are captured, not just echoed.
OUTPUT "tests/data/output_status_q_mock_capture.dat"
USE MOCK
SAVE "tests/data/output_status_q_mock_save.csv"
RUN
OUTPUT
SYSTEM "echo === captured ==="
SYSTEM "cat tests/data/output_status_q_mock_capture.dat"
SYSTEM "rm -f tests/data/output_status_q_mock_save.csv tests/data/output_status_q_mock_capture.dat"
QUIT
