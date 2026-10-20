# Writes a CSV with 90000 columns whose header line is ~1.3 MB (over the old
# 1 MiB line cap) and 2 data rows.  Used by tests/csv_long_line.cmd (F24).
BEGIN {
  for (i = 0; i < 90000; i++) printf "%sCOLUMN_%07d", (i ? "," : ""), i
  printf "\n"
  for (r = 1; r <= 2; r++) {
    for (i = 0; i < 90000; i++) printf "%s%d", (i ? "," : ""), r
    printf "\n"
  }
}
