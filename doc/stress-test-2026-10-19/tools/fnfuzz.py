import re,subprocess,itertools,glob,sys,random,os
S='/home/jries/Develop/sdata/bin/sdata'
ar={}
for f in glob.glob('/home/jries/Develop/sdata-core/src/*.adb'):
    for m in re.finditer(r'Register_Arity\s*\("([A-Z0-9$]+)",\s*(\d+),\s*([A-Za-z0-9_\']+)\)',open(f).read()):
        lo=int(m.group(2)); hi=m.group(3); hi=lo if not hi.isdigit() else int(hi)
        if m.group(3).startswith('Natural'): hi=min(lo+2,4)
        ar[m.group(1)]=(lo,hi)
skip={'SHELL','TIMER','TIME$','DATE$','RAN','RANDOM','RND','URN','ZRN','ERN','GRN','BRN','TRN','FRN','XRN','WRN','LRN','PRN','NRN','MRN','RAND'}
nums=['0','-1','1','0.5','1e308','-1e308','1e-308','1e19','MAXINT()','MININT()','.','2.5','100','-0.0','1e15']
strs=['""','"abc"','"é日"','"1e5"']
random.seed(3)
bad=[]
tot=0
names=sorted(ar)
for n in names:
    if n in skip or n.startswith(('ERR','ERL')): continue
    lo,hi=ar[n]
    for k in range(lo,hi+1):
        combos=[]
        if k==0: combos=[()]
        else:
            pool=nums if not n.endswith('$') or n in ('CHR$','HEX$','OCT$','BIN$','STR$','NUM$') else nums+strs
            if n in ('LEN','LEFT$','RIGHT$','MID$','SEG$','TRIM$','LTRIM$','RTRIM$','UCASE$','LCASE$','UPPER$','LOWER$','POS','INSTR','INDEX','MATCH','ASCII','ASC','VAL','HEX','ORD','NUM','SHELL','LAGC$','NEXTC$','OBSC$'): pool=nums+strs
            allc=list(itertools.product(pool,repeat=k)) if len(pool)**k<=400 else [tuple(random.choice(pool) for _ in range(k)) for _ in range(300)]
            combos=allc if len(allc)<=300 else random.sample(allc,300)
        # build one script per function with each combo in its own REPEAT block? use -k to continue after errors
        lines=[]
        for c in combos:
            lines.append('REPEAT 1')
            lines.append(f'LET Q = {n}({",".join(c)})' if not n.endswith('$') else f'LET Q$ = {n}({",".join(c)})')
            lines.append('PRINT "<<" Q "|' + ','.join(x.replace('"','\'') for x in c).replace('"','') + '>>"' if False else 'PRINT Q')
            lines.append('RUN')
        open('ff.cmd','w').write('\n'.join(lines)+'\n')
        try:
            p=subprocess.run([S,'-k','ff.cmd'],capture_output=True,text=True,errors='replace',timeout=120,stdin=subprocess.DEVNULL)
        except subprocess.TimeoutExpired:
            bad.append((n,k,'TIMEOUT')); continue
        o=p.stdout+p.stderr; tot+=len(combos)
        for pat,label in ((r'\.adb:\d+','ADA-LEAK'),(r'CONSTRAINT_ERROR|PROGRAM_ERROR|STORAGE_ERROR|intman','EXC'),(r'\bNaN\b','NaN'),(r'check failed','CHECK')):
            if re.search(pat,o): 
                ex=[l for l in o.splitlines() if re.search(pat,l)][:2]
                bad.append((n,k,label,ex)); break
        if p.returncode not in (0,1): bad.append((n,k,'RC%d'%p.returncode))
print('calls tried (approx):',tot)
for b in bad: print(b)
