# Runs the public csv-spectrum suite (github.com/max-mapper/csv-spectrum) through sdata USE+SAVE and compares with the expected JSON.
# Usage: mkdir spec && cd spec && fetch csvs/*.csv and json/*.json (names spec_<case>.csv/.json), then python3 ../csvspectrum.py
import json,csv,subprocess,glob
SDATA='/home/jries/Develop/sdata/bin/sdata'
def norm(v):
    try:
        f=float(v); return repr(int(f)) if f==int(f) else repr(f)
    except Exception: return v
for j in sorted(glob.glob('spec_*.json')):
    n=j[:-5]; exp=json.load(open(j))
    open('r.cmd','w').write(f'USE "{n}.csv"\nSAVE "out_{n}.csv"\nRUN\n')
    p=subprocess.run([SDATA,'r.cmd'],capture_output=True,text=True,errors='replace')
    rows=list(csv.reader(open(f'out_{n}.csv',newline='',encoding='utf-8')))
    hdr=[h.rstrip('$%').lower() for h in rows[0]] if rows else []
    got=[{h:norm(v) for h,v in zip(hdr,r)} for r in rows[1:]]
    ex=[{k.lower():norm(v) for k,v in e.items()} for e in exp]
    print(f'{n:28s}','OK' if got==ex else f'MISMATCH expected {ex} got {got}')
