# writes rows.csv with 400,000 rows; then: USE "rows.csv" / STATS X /STATS=N /NOPRINT
open("rows.csv","w").write("X,G\n"+"".join(f"{i%977+0.5},0\n" for i in range(400000)))
