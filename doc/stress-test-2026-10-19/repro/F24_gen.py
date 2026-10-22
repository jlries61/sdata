# writes F24_wide.csv: 200,000 columns x 1 data row; USE it with F24.cmd (expect 200000 columns)
n = 200000
open("F24_wide.csv", "w").write(",".join("C%d" % i for i in range(n)) + "\n" + ",".join(["1"] * n) + "\n")
