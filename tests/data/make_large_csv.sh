#!/bin/sh
# Writes a ~10 MB many-row CSV (test fixture generator for charset_large_file).
out=tests/data/cs_large.csv
printf 'A$\n' > $out
line=$(head -c 99 /dev/zero | tr '\000' x)
i=0
while [ $i -lt 100 ]; do printf '%s\n' "$line"; i=$((i+1)); done > tests/data/cs_blk.tmp
i=0
while [ $i -lt 1000 ]; do cat tests/data/cs_blk.tmp >> $out; i=$((i+1)); done
rm -f tests/data/cs_blk.tmp
