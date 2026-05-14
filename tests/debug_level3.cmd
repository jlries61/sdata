-- Verify --debug=3: I/O + record headers + assignments all present
SYSTEM "./bin/sdata -q --debug=3 tests/data/debug_inner.cmd 2>/tmp/_sdata_dbg.txt"
SYSTEM "grep -qF 'USE: opened' /tmp/_sdata_dbg.txt"
SYSTEM "grep -qF -- '-- record 1' /tmp/_sdata_dbg.txt"
SYSTEM "grep -qF 'RUN complete' /tmp/_sdata_dbg.txt"
SYSTEM "test $(grep -cF 'LET X =' /tmp/_sdata_dbg.txt) -gt 0"
SYSTEM "echo 'debug_level3: OK'"
