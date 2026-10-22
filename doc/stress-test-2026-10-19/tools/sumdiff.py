import json,sys
from collections import Counter
rs=[json.loads(l) for l in open(sys.argv[1])]
print(len(rs),Counter(r.get('status') for r in rs))
print('internal errs:',[r['file'] for r in rs if r.get('internal_err')])
print('rc!=0:',[(r['file'],r.get('rc')) for r in rs if r.get('rc') not in (0,None)])
for r in rs:
    if r.get('status') not in ('OK',):
        print('*',r['file'],r.get('size'),r.get('status'),r.get('ndiffs'),r.get('diffs',[])[:4],'|',(r.get('log') or '')[:260].replace('\n',' / '))
