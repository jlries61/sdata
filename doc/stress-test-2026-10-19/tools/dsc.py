import subprocess
from scipy import stats
tests=[]
for p,n,pr in [(0.5,10,0.5),(0.01,10,0.5),(0.999,100,0.1),(1e-9,50,0.5),(0.5,1,0.5),(0.2,1000,0.01)]:
    tests.append((f'NIF({p},{n},{pr})',stats.binom.ppf(p,n,pr)))
for p,l in [(0.5,3),(0.99,10),(0.001,100),(0.5,0.01),(0.9999,1000)]:
    tests.append((f'PIF({p},{l})',stats.poisson.ppf(p,l)))
for p in [0.5]: pass
tests += [('NCF(5,10,0)',1.0),('NCF(5,10,1)',0.0),('NDF(0,10,0)',1.0),('NCF(2.5,10,0.5)',stats.binom.cdf(2,10,.5)),('NDF(2.5,10,.5)',0.0),('PCF(2.5,3)',stats.poisson.cdf(2,3)),('PDF(1000,1000)',stats.poisson.pmf(1000,1000)),('NDF(500,1000,0.5)',stats.binom.pmf(500,1000,.5)),('NCF(-1,10,0.5)',0.0),('ZCF(1e308)',1.0),('ZIF(0)', float('-inf')), ('ZIF(1)', float('inf')),('XCF(0,5)',0.0),('TCF(1e300,3)',1.0),('FCF(0,1,1)',0.0),('BCF(0,1,1)',0.0),('BCF(1,1,1)',1.0),('BDF(0,0.5,0.5)',float('inf')),('GCF(0,1,1)',0.0),('XDF(0,2)',0.5),('XDF(0,1)',float('inf')),('TDF(0,1e10)',0.3989422804014327)]
for e,v in tests:
    open('d.cmd','w').write(f'DIGITS 15\nREPEAT 1\nLET V = {e}\nPRINT V\nRUN\n')
    p=subprocess.run(['/home/jries/Develop/sdata/bin/sdata','d.cmd'],capture_output=True,text=True)
    out=(p.stdout+p.stderr).strip().splitlines()
    print(f'{e:28s} expect {v!s:22s} got {out[0] if out else None}', '' if len(out)<2 or out[0].startswith(('0','1','2','3','4','5','6','7','8','9','-','I','N')) else out[:2])
