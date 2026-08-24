-- Subscript called by submit_loop_declarative*.cmd (PD-2/ADR-058). A lone
-- SAVE is an uncontroversially Declarative-tier statement (per its own HELP
-- text), used to exercise ADR-056's declarative-in-loop warning when this
-- file is SUBMITted from inside a loop.
SAVE "tests/data/submit_declarative_sub_out.csv"
