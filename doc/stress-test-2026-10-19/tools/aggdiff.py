import sys,os,subprocess,pandas as pd,numpy as np,json
for path in sys.argv[1:]:
    try: df=pd.read_csv(path,low_memory=False,encoding_errors='replace')
    except Exception as e: print(os.path.basename(path),'pandas fail'); continue
    if len(df)<20 or len(df)>2_000_000: continue
    num=[c for c in df.columns if pd.api.types.is_numeric_dtype(df[c]) and df[c].nunique()>3 and ' ' not in str(c) and '.' not in str(c)]
    grp=[c for c in df.columns if 1<df[c].nunique()<=30 and ' ' not in str(c) and '.' not in str(c) and c not in num[:1]]
    if not num or not grp: continue
    v=num[0]; g=grp[0]
    gs=str(g).upper()+('$' if not pd.api.types.is_numeric_dtype(df[g]) and not str(g).endswith('$') else '')
    vs=str(v).upper()
    out=f'ag/out.csv'
    if os.path.exists(out): os.unlink(out)
    open('ag/x.cmd','w').write(f'USE "{path}"\nBY {gs}\nSAVE "{out}"\nAGGREGATE S=SUM({vs}) M=MEAN({vs}) N=N() NM=NMISS({vs}) MN=MIN({vs}) MX=MAX({vs}) MD=MEDIAN({vs}) SD=STD({vs}) P10=PCTL({vs},10)\n')
    p=subprocess.run(['/home/jries/Develop/sdata/bin/sdata','ag/x.cmd'],capture_output=True,text=True,errors='replace',timeout=120)
    if not os.path.exists(out): print(os.path.basename(path),g,v,'NO OUTPUT',p.stdout[-150:].replace('\n','/')); continue
    s=pd.read_csv(out,low_memory=False,keep_default_na=False,na_values=[''])
    # pandas expected
    d=df[[g,v]].copy()
    d[g]=d[g].astype(str) if not pd.api.types.is_numeric_dtype(d[g]) else d[g]
    e=d.groupby(g,dropna=False)[v].agg(S=lambda x:x.sum(min_count=1),M='mean',N='size',NM=lambda x:x.isna().sum(),MN='min',MX='max',MD='median',SD='std',P10=lambda x:x.quantile(.1)).reset_index()
    if len(e)!=len(s): print(os.path.basename(path),g,v,'GROUPS',len(s),len(e)); continue
    bad=[]
    sg=s.iloc[:,0]; 
    e=e.sort_values(g,key=lambda x:x.astype(str)).reset_index(drop=True)
    s=s.assign(_k=s.iloc[:,0].astype(str)).sort_values('_k').reset_index(drop=True)
    # align by key string
    em={str(k):i for i,k in enumerate(e[g])}
    for i,row in s.iterrows():
        k=str(row.iloc[0])
        k2=k if k in em else (k.rstrip('0').rstrip('.') if '.' in k else k)
        if k not in em:
            try:
                k=str(float(k)) if str(float(k)) in em else str(int(float(k)))
            except: pass
        if k not in em: bad.append(('key',k)); continue
        r=e.iloc[em[k]]
        for c in ['S','M','N','NM','MN','MX','MD','SD','P10']:
            a=row[c]; b=r[c]
            if pd.isna(a) and pd.isna(b): continue
            if pd.isna(a) or pd.isna(b) or abs(a-b)>1e-6*max(1,abs(b)): bad.append((k,c,a,b))
    print(os.path.basename(path),g,v,len(s),'OK' if not bad else bad[:4])
