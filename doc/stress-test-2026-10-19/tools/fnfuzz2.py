import subprocess,itertools,re,sys
S='/home/jries/Develop/sdata/bin/sdata'
pool=['0','-1','1','0.5','1e308','1e-308','1e19','2.5','100','1e15','MAXINT()']
targets={'COSD':1,'SIND':1,'TAND':1,'LDF':1,'LTW':1,'ROUND':2,'NCF':3,'NDF':3,'XCF':2,'XDF':2,'PDF':2,'GDF':3,'MDF':3,'TCF':2,'TIF':2,'BCF':3,'BIF':3,'FCF':3,'FIF':3,'COSH':1,'HEX':1,'PCF':2}
out={}
for fn,k in targets.items():
    hits=[]
    combos=list(itertools.product(pool,repeat=k))
    for c in combos:
        args=','.join(c)
        open('f2.cmd','w').write(f'REPEAT 1\nLET Q = {fn}({args})\nPRINT Q\nRUN\n')
        try:
            p=subprocess.run([S,'f2.cmd'],capture_output=True,text=True,errors='replace',timeout=8,stdin=subprocess.DEVNULL)
            o=(p.stdout+p.stderr)
            if re.search(r'\bNaN\b',o) and 'Error' not in o: hits.append(('NaN',args))
            elif re.search(r'\.adb',o): hits.append(('ADA',args))
        except subprocess.TimeoutExpired:
            hits.append(('HANG>8s',args))
    out[fn]=hits
    kinds={}
    for h in hits: kinds.setdefault(h[0],[]).append(h[1])
    print(fn,{kk:(len(v),v[:3]) for kk,v in kinds.items()},flush=True)
