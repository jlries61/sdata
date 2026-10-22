import subprocess
def run(body):
    open('thr.cmd','w').write(body)
    p=subprocess.run(['/home/jries/Develop/sdata/bin/sdata','thr.cmd'],capture_output=True,text=True,stdin=subprocess.DEVNULL,timeout=60)
    return 'STORAGE' in p.stdout+p.stderr
def bis(mk,lo,hi):
    while hi-lo>1:
        m=(lo+hi)//2
        if run(mk(m)): hi=m
        else: lo=m
    return lo
print('parens',bis(lambda n:'REPEAT 1\nLET X = '+'('*n+'1'+')'*n+'\nPRINT X\nRUN\n',10,100000))
print('plus',bis(lambda n:'REPEAT 1\nLET X = 1'+'+1'*n+'\nPRINT X\nRUN\n',10,300000))
print('if',bis(lambda n:'REPEAT 1\n'+'IF 1 THEN\n'*n+'PRINT 1\n'+'END IF\n'*n+'RUN\n',10,20000))
print('for',bis(lambda n:'REPEAT 1\n'+''.join(f'FOR I{i} = 1 TO 1\n' for i in range(n))+'PRINT 1\n'+'NEXT\n'*n+'RUN\n',10,5000))
print('calls',bis(lambda n:'REPEAT 1\nLET X = '+'ABS('*n+'1'+')'*n+'\nPRINT X\nRUN\n',10,50000))
