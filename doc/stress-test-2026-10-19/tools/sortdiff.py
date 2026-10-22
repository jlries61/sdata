import sys,subprocess,os,pandas as pd,numpy as np
files=sys.argv[1:]
for path in files:
    df=pd.read_csv(path,low_memory=False,encoding_errors='replace')
    cols=list(df.columns)
    num=[c for c in cols if pd.api.types.is_numeric_dtype(df[c]) and df[c].nunique()>1 and ' ' not in str(c)]
    chr_=[c for c in cols if not pd.api.types.is_numeric_dtype(df[c]) and ' ' not in str(c)]
    keysets=[]
    if num: keysets.append([num[0]])
    if len(num)>1: keysets.append([num[1],num[0]])
    if chr_ and num: keysets.append([chr_[0],num[0]])
    for ks in keysets:
        names=[str(k).upper() for k in ks]
        # sdata names for char cols have $ suffix
        def sdname(c):
            return (str(c).upper()+'$') if not pd.api.types.is_numeric_dtype(df[c]) and not str(c).endswith('$') else str(c).upper()
        sn=[sdname(k) for k in ks]
        out='sortout.csv'
        if os.path.exists(out): os.unlink(out)
        open('so.cmd','w').write(f'USE "{path}"\nLET ORIG = RECNO()\nRUN\nSORT {" ".join(sn)}\nSAVE "{out}"\nRUN\n')
        p=subprocess.run(['/home/jries/Develop/sdata/bin/sdata','so.cmd'],capture_output=True,text=True,errors='replace',timeout=300)
        if not os.path.exists(out): print(os.path.basename(path),ks,'NO OUTPUT',p.stdout[-200:].replace('\n','/')); continue
        s=pd.read_csv(out,low_memory=False,encoding_errors='replace')
        # expected
        d=df.copy(); d['_i']=np.arange(len(d))
        exp=d.sort_values(ks+['_i'],kind='stable',na_position='first')
        if len(s)!=len(exp): print(os.path.basename(path),ks,'ROWCOUNT',len(s),len(exp)); continue
        # compare key columns sequences
        bad=0
        for k,sk in zip(ks,sn):
            a=s[sk] if sk in s.columns else s[str(k).upper()] if str(k).upper() in s.columns else None
            if a is None: print('missing col',sk,list(s.columns)[:5]); bad=1; break
            e=exp[k].reset_index(drop=True)
            if not ((a.astype(str).values==e.astype(str).values).all() or np.allclose(pd.to_numeric(a,errors='coerce').fillna(-9e99).values,pd.to_numeric(e,errors='coerce').fillna(-9e99).values)): bad=1
        # stability: compare full first column of rows via _i? compare all columns row-wise on a hash
        stab = ('ORIG' in s.columns) and (s['ORIG'].values==(exp['_i'].values+1)).all()
        print(os.path.basename(path),ks,('KEYS-OK' if not bad else 'KEYS-DIFF')+(' STABLE' if stab else ' ORDER-DIFF'), len(df))
