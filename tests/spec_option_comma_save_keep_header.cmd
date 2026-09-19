-- SAVE shares the spec-option parser. SAVE is declarative: the file is written at RUN.
USE "tests/data/display_rows.csv"
RUN
SAVE "tests/data/spec_option_comma_save_out.csv"(KEEP=ID, HEADER=YES)
RUN
SYSTEM "cat tests/data/spec_option_comma_save_out.csv"
SYSTEM "rm -f tests/data/spec_option_comma_save_out.csv"
QUIT
