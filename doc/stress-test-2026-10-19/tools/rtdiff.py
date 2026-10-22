import sys,os,subprocess,json,pandas as pd,numpy as np,re,time
def same(a,b):
    if a.shape!=b.shape: return f'shape {a.shape} vs {b.shape}'
    if list(a.columns)!=list(b.columns): return f'cols differ {list(a.columns)[:4]} vs {list(b.columns)[:4]}'
    for c in a.columns:
        x,y=a[c],b[c]
        if pd.api.types.is_numeric_dtype(x) and pd.api.types.is_numeric_dtype(y):
            xv=x.astype(float).values; yv=y.astype(float).values
            ok=((xv==yv)|(np.isnan(xv)&np.isnan(yv))).all()
            if not ok:
                i=int(np.where(~((xv==yv)|(np.isnan(xv)&np.isnan(yv))))[0][0]); return f'col {c} row {i}: {xv[i]!r} vs {yv[i]!r}'
        else:
            xs=x.fillna('').astype(str).values; ys=y.fillna('').astype(str).values
            if not (xs==ys).all():
                i=int(np.where(xs!=ys)[0][0]); return f'col {c} row {i}: {xs[i]!r} vs {ys[i]!r}'
    return None
for path in sys.argv[1:]:
    b=os.path.basename(path).replace('.','_')
    res={}
    for fmt in ('xlsx','ods'):
        for f in (f'rt/{b}.a.csv',f'rt/{b}.{fmt}',f'rt/{b}.c.csv'):
            if os.path.exists(f): os.unlink(f)
        cmd=f'USE "{path}"\nSAVE "rt/{b}.a.csv"\nRUN\nUSE "{path}"\nSAVE "rt/{b}.{fmt}"\nRUN\nUSE "rt/{b}.{fmt}"\nSAVE "rt/{b}.c.csv"\nRUN\n'
        open('rt/x.cmd','w').write(cmd)
        t=time.time()
        try: p=subprocess.run(['/home/jries/Develop/sdata/bin/sdata','rt/x.cmd'],capture_output=True,text=True,errors='replace',timeout=300)
        except subprocess.TimeoutExpired: res[fmt]='TIMEOUT'; continue
        if not os.path.exists(f'rt/{b}.c.csv') or not os.path.exists(f'rt/{b}.a.csv'):
            res[fmt]='FAIL: '+(p.stdout+p.stderr).strip().splitlines()[-1][:120] if (p.stdout+p.stderr).strip() else 'FAIL'; continue
        a=pd.read_csv(f'rt/{b}.a.csv',low_memory=False,dtype=None); c=pd.read_csv(f'rt/{b}.c.csv',low_memory=False)
        res[fmt]=same(a,c) or 'OK'
        for f in (f'rt/{b}.{fmt}',f'rt/{b}.c.csv'):
            if os.path.exists(f): os.unlink(f)
    # also: csv->csv idempotence vs original via pandas
    print(json.dumps({'file':os.path.basename(path),**res}),flush=True)
