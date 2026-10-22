#!/bin/bash
# rd.sh file  -> USE + NAMES + DISPLAY (+ SAVE roundtrip)
cd .
f=$1
printf 'USE "csv/%s"\nDISPLAY /FIRST=8\nNAMES\n' "$f" > rd.cmd
timeout 30 ~/Develop/sdata/bin/sdata ${SD_OPTS} rd.cmd </dev/null 2>&1 | head -${H:-30}
echo "[rc=${PIPESTATUS[0]}]"
