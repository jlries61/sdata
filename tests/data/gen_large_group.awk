# Writes a 2-column CSV with 360000 rows (G alternates 0/1, X cycles 0..9).
BEGIN {
  print "G,X"
  for (i = 1; i <= 360000; i++) print (i % 2) "," (i % 10)
}
