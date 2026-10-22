import sys,os,subprocess,json,math,glob,time,csv,io
import pandas as pd, numpy as np
from concurrent.futures import ThreadPoolExecutor
SD='/home/jries/Develop/sdata/bin/sdata'
OUT='diff'
def one(path):
    try:
        return one_(path)
    except Exception as e:
        return {'file':os.path.basename(path),'status':'DRIVER_EXC '+repr(e)[:150]}
def one_(path):
    base=os.path.basename(path)
    key=base.replace('/','_')
    res={'file':base,'size':os.path.getsize(path)}
    out=f'{OUT}/{key}.stats.csv'
    cmd=f'{OUT}/{key}.cmd'
    if os.path.exists(out): os.unlink(out)
    open(cmd,'w').write(f'USE "{path}"\nSAVE "{out}"\nSTATS /STATS=N NMISS MEAN MIN MAX STD /NOPRINT\n')
    t=time.time()
    try:
        p=subprocess.run([SD,cmd],capture_output=True,text=True,timeout=int(os.environ.get('TMO','300')),stdin=subprocess.DEVNULL,errors='replace')
    except subprocess.TimeoutExpired:
        res['status']='TIMEOUT'; return res
    res['secs']=round(time.time()-t,1); res['rc']=p.returncode
    txt=p.stdout+p.stderr
    res['log']=txt[:1500]
    res['warnings']=txt.count('Warning')
    import re
    if re.search(r'\.adb:|raised|STORAGE_ERROR|CONSTRAINT_ERROR|check failed',txt): res['internal_err']=True
    m=re.search(r'Dataset opened.*',txt)
    if not os.path.exists(out):
        res['status']='NOSTATS'; return res
    sd=pd.read_csv(out)
    res['sd_cols']=len(sd)
    try:
        df=pd.read_csv(path,low_memory=False,encoding_errors='replace')
    except Exception as e:
        res['status']='PANDAS_FAIL '+str(e)[:100]; return res
    res['pd_rows']=len(df); res['pd_cols']=df.shape[1]
    # sdata row count
    mm=re.search(r'(\d[\d,]*) (?:records|rows)',txt)
    pdnum={}
    for c in df.columns:
        if pd.api.types.is_numeric_dtype(df[c]): pdnum[str(c).strip().upper()]=df[c]
    diffs=[]
    nm=0
    for _,r in sd.iterrows():
        name=str(r['_NAME_$']).strip()
        b=name.rstrip('$%')
        if name.endswith('$'): continue
        if b not in pdnum: 
            res.setdefault('unmatched',[]).append(name); continue
        s=pdnum[b].astype(float)
        s=s.replace([np.inf,-np.inf],np.nan)
        exp={'N':s.count(),'NMISS':s.isna().sum(),'MEAN':s.mean(),'MIN':s.min(),'MAX':s.max(),'STD':s.std(ddof=1)}
        for k,v in exp.items():
            g=r[k]
            if pd.isna(v) and pd.isna(g): continue
            ok = (not pd.isna(v)) and (not pd.isna(g)) and (abs(g-v)<=1e-6*max(1,abs(v)) or abs(g-v)<=1e-9)
            if not ok: diffs.append((name,k,float(g) if not pd.isna(g) else None,float(v) if not pd.isna(v) else None))
        nm+=1
    res['compared']=nm; res['diffs']=diffs[:12]; res['ndiffs']=len(diffs)
    res['status']='OK' if not diffs else 'DIFF'
    return res
if __name__=='__main__':
    files=sys.argv[1:]
    with ThreadPoolExecutor(4) as ex:
        for r in ex.map(one,files):
            print(json.dumps(r),flush=True)
