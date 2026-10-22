import subprocess,math,itertools,re
from scipy import stats, special
tests=[]  # (expr string, expected float)
def add(e,v): tests.append((e,v))
for x in [-40,-8,-3,-1,0,0.5,2,5,8,37]:
    add(f'ZCF({x})',stats.norm.cdf(x)); add(f'ZDF({x})',stats.norm.pdf(x))
for x,m,s in [(1,0,2),(10,5,0.1),(-3,2,5)]:
    add(f'ZCF({x},{m},{s})',stats.norm.cdf(x,m,s)); add(f'ZDF({x},{m},{s})',stats.norm.pdf(x,m,s))
for p in [1e-300,1e-15,1e-6,0.001,0.1,0.5,0.9,0.999,1-1e-9]:
    add(f'ZIF({p!r})',stats.norm.ppf(p))
for x,df in [(0.5,1),(3,2),(10,5),(0.01,100),(50,10),(1e-5,3),(300,30)]:
    add(f'XCF({x},{df})',stats.chi2.cdf(x,df)); add(f'XDF({x},{df})',stats.chi2.pdf(x,df))
for p,df in [(0.5,1),(0.95,10),(0.999,100),(1e-6,5),(0.99999,3)]:
    add(f'XIF({p},{df})',stats.chi2.ppf(p,df))
for t,df in [(0,1),(1,1),(-2,5),(2.5,30),(10,3),(-40,2),(0.1,1000),(3,0.5)]:
    add(f'TCF({t},{df})',stats.t.cdf(t,df)); add(f'TDF({t},{df})',stats.t.pdf(t,df))
for p,df in [(0.5,3),(0.975,10),(0.999,2),(0.01,30),(1e-6,4)]:
    add(f'TIF({p},{df})',stats.t.ppf(p,df))
for f,a,b in [(1,1,1),(2.5,3,10),(0.1,10,3),(30,5,5),(1e-3,2,50)]:
    add(f'FCF({f},{a},{b})',stats.f.cdf(f,a,b)); add(f'FDF({f},{a},{b})',stats.f.pdf(f,a,b))
for p,a,b in [(0.5,3,10),(0.95,5,5),(0.999,2,50),(0.01,10,10)]:
    add(f'FIF({p},{a},{b})',stats.f.ppf(p,a,b))
for g,p in [(0.5,1),(3,2),(10,5),(0.01,0.5),(100,90),(1,0.1)]:
    add(f'GCF({g},{p})',stats.gamma.cdf(g,p)); add(f'GDF({g},{p})',stats.gamma.pdf(g,p))
for p,a in [(0.5,1),(0.95,3),(0.01,0.5),(0.999,20)]:
    add(f'GIF({p},{a})',stats.gamma.ppf(p,a))
for b,p,q in [(0.5,1,1),(0.2,2,3),(0.9,0.5,0.5),(0.01,10,20),(0.99,30,2)]:
    add(f'BCF({b},{p},{q})',stats.beta.cdf(b,p,q)); add(f'BDF({b},{p},{q})',stats.beta.pdf(b,p,q))
for pr,p,q in [(0.5,2,3),(0.1,1,1),(0.99,5,0.5),(0.001,3,3)]:
    add(f'BIF({pr},{p},{q})',stats.beta.ppf(pr,p,q))
for x in [0,0.5,1,5,20]:
    add(f'ECF({x})',stats.expon.cdf(x)); add(f'EDF({x})',stats.expon.pdf(x))
for p in [0,0.1,0.5,0.99]:
    add(f'EIF({p})',stats.expon.ppf(p))
for x,n,p in [(0,10,0.5),(3,10,0.3),(10,10,0.9),(50,100,0.5),(5,1000,0.01),(0,1,0.5)]:
    add(f'NCF({x},{n},{p})',stats.binom.cdf(x,n,p)); add(f'NDF({x},{n},{p})',stats.binom.pmf(x,n,p))
for x,l in [(0,1),(3,2.5),(10,3),(100,100),(0,50),(30,0.1)]:
    add(f'PCF({x},{l})',stats.poisson.cdf(x,l)); add(f'PDF({x},{l})',stats.poisson.pmf(x,l))
for x,p,q in [(1,1,1),(2,3,0.5),(0.1,2,2),(5,1,3)]:
    add(f'WCF({x},{p},{q})',stats.weibull_min.cdf(x,q,scale=p)); add(f'WDF({x},{p},{q})',stats.weibull_min.pdf(x,q,scale=p))
for p,a,b in [(0.5,2,3),(0.1,1,1),(0.99,2,0.5)]:
    add(f'WIF({p},{a},{b})',stats.weibull_min.ppf(p,b,scale=a))
for x in [-30,-3,0,2,10]:
    add(f'LCF({x})',stats.logistic.cdf(x)); add(f'LDF({x})',stats.logistic.pdf(x))
for p in [0.001,0.5,0.99]:
    add(f'LIF({p})',stats.logistic.ppf(p))
for x in [-0.3,0,1,10,1e5]:
    add(f'LTW({x})',special.lambertw(x).real)
lines=['DIGITS 17','REPEAT 1']
for i,(e,v) in enumerate(tests): lines.append(f'LET V{i} = {e}')
lines.append('RUN'); lines.append('PRINT '+' '.join(f'"|" V{i}' for i in range(len(tests))))
# per-expression scripts to isolate errors: run all separately
import tempfile,os
bad=[]
for i,(e,v) in enumerate(tests):
    s=f'DIGITS 17\nREPEAT 1\nLET V = {e}\nPRINT V\nRUN\n'
    open('d.cmd','w').write(s)
    p=subprocess.run(['/home/jries/Develop/sdata/bin/sdata','d.cmd'],capture_output=True,text=True)
    out=p.stdout.strip().splitlines()
    try:
        got=float(out[0])
    except Exception:
        bad.append((e,'ERR/MISSING',(p.stdout+p.stderr).strip().replace('\n',' / ')[:100],v)); continue
    if not (abs(got-v)<=1e-9*max(abs(v),1e-300) or abs(got-v)<1e-14):
        bad.append((e,got,v,f'rel={abs(got-v)/max(abs(v),1e-300):.2e}'))
print(len(tests),'tests;',len(bad),'mismatches')
for b in bad: print(b)
