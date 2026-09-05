-- sdata#81 / ADR-065: "Dataset opened: ..." (real-file USE, sdata-core's
-- Open_Input) and multi-target SAVE's own "Dataset saved: ..." (sdata's
-- Commit_Step, a different call site than single-target SAVE) must also
-- reach the OUTPUT-redirected transcript unconditionally under -q.
OUTPUT "tests/data/output_status_q_multisave_capture.dat"
USE "tests/data/merge_a.csv"
SAVE "tests/data/output_status_q_multisave_p.csv" AS P, "tests/data/output_status_q_multisave_q.csv" AS Q
RUN
OUTPUT
SYSTEM "cat tests/data/output_status_q_multisave_capture.dat"
SYSTEM "rm -f tests/data/output_status_q_multisave_p.csv tests/data/output_status_q_multisave_q.csv tests/data/output_status_q_multisave_capture.dat"
QUIT
