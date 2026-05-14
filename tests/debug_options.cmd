-- Verify OPTIONS DEBUG N sets level at runtime (level 1: record headers absent)
SYSTEM "./bin/sdata -q tests/data/debug_options_inner.cmd 2>/tmp/_sdata_dbg.txt"
SYSTEM "grep -qF 'USE: opened' /tmp/_sdata_dbg.txt"
SYSTEM "grep -qF 'RUN complete' /tmp/_sdata_dbg.txt"
SYSTEM "test $(grep -cF -- '-- record' /tmp/_sdata_dbg.txt) -eq 0"
SYSTEM "test $(grep -cF 'LET X' /tmp/_sdata_dbg.txt) -eq 0"
SYSTEM "echo 'debug_options: OK'"
