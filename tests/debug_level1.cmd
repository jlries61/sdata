-- Verify --debug=1: I/O traces present; record headers and assignments absent
SYSTEM "./bin/sdata -q --debug=1 tests/data/debug_inner.cmd 2>/tmp/_sdata_dbg.txt"
SYSTEM "grep -qF 'USE: opened' /tmp/_sdata_dbg.txt"
SYSTEM "grep -qF 'RUN complete' /tmp/_sdata_dbg.txt"
SYSTEM "test $(grep -cF -- '-- record' /tmp/_sdata_dbg.txt) -eq 0"
SYSTEM "test $(grep -cF 'LET X' /tmp/_sdata_dbg.txt) -eq 0"
SYSTEM "echo 'debug_level1: OK'"
