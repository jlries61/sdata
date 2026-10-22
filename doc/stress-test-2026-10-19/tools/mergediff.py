import numpy as np,pandas as pd,subprocess,os,itertools
rng=np.random.default_rng(11)
def run(cmd):
    open('mg/x.cmd','w').write(cmd)
    p=subprocess.run(['/home/jries/Develop/sdata/bin/sdata','mg/x.cmd'],capture_output=True,text=True,errors='replace',timeout=120)
    return p.stdout+p.stderr
bad=0
for trial in range(40):
    na,nb=rng.integers(1,60,2)
    kc=rng.integers(2,12)
    keys=np.arange(kc)
    dupA = trial%4>=2; dupB = trial%4==3
    ka=rng.choice(keys,na,replace=True) if dupA else rng.permutation(keys)[:min(na,kc)]
    kb=rng.choice(keys+3,nb,replace=True) if dupB else rng.permutation(keys+3)[:min(nb,kc)]
    A=pd.DataFrame({'K':ka,'X':rng.integers(0,100,len(ka)),'S$':[f's{i}' for i in range(len(ka))]})
    B=pd.DataFrame({'K':kb,'Y':rng.integers(0,100,len(kb))})
    # inject missing key sometimes
    if trial%5==0: A.loc[0,'K']=np.nan
    A.to_csv('mg/a.csv',index=False); B.to_csv('mg/b.csv',index=False)
    # JOIN (inner cartesian)
    if os.path.exists('mg/o.csv'): os.unlink('mg/o.csv')
    out=run('USE "mg/a.csv", "mg/b.csv" /BY=K /JOIN\nSAVE "mg/o.csv"\nRUN\n')
    try:
        o=pd.read_csv('mg/o.csv'); 
    except Exception: o=None
    e=A.merge(B,on='K',how='inner')
    # sdata: missing keys as a group matched with missing? pandas matches NaN with NaN in merge -> remove for comparison if B has NaN (B has none)
    def canon(d,cols): 
        return sorted(map(tuple,d[cols].fillna(-1).astype(float).values.tolist())) if len(d) else []
    if len(e)==0: pass
    elif o is None or canon(o,['K','X','Y'])!=canon(e,['K','X','Y']):
        bad+=1; print('JOIN mismatch trial',trial,'dupA',dupA,'dupB',dupB,'sd rows',None if o is None else len(o),'pd rows',len(e)); 
    # match-merge (no JOIN) only valid expectation when keys unique both sides => full outer
    if not dupA and not dupB:
        if os.path.exists('mg/o.csv'): os.unlink('mg/o.csv')
        run('USE "mg/a.csv", "mg/b.csv" /BY=K\nSAVE "mg/o.csv"\nRUN\n')
        o=pd.read_csv('mg/o.csv'); e=A.merge(B,on='K',how='outer')
        if canon(o,['K','X','Y'])!=canon(e,['K','X','Y']):
            bad+=1; print('MATCHMERGE mismatch trial',trial,len(o),len(e))
    # interleave: concat + stable sort by K (missing first)
    if os.path.exists('mg/o.csv'): os.unlink('mg/o.csv')
    run('USE "mg/a.csv", "mg/b.csv" /BY=K /INTERLEAVE\nSAVE "mg/o.csv"\nRUN\n')
    o=pd.read_csv('mg/o.csv'); e=pd.concat([A,B],ignore_index=True)
    if len(o)!=len(e) or canon(o,['K'])!=canon(e,['K']) or list(o['K'].fillna(-1))!=sorted(o['K'].fillna(-1)):
        bad+=1; print('INTERLEAVE mismatch trial',trial,len(o),len(e), list(o['K'].fillna(-1))[:10])
print('done; mismatches:',bad)
