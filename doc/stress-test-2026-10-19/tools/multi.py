import sys,subprocess,tempfile,os,re
# usage: multi.py file [opts...]; snippets separated by lines '####'
src=open(sys.argv[1]).read().split('\n####\n')
opts=sys.argv[2:]
for i,s in enumerate(src):
    s=s.strip('\n')
    if not s.strip(): continue
    with tempfile.NamedTemporaryFile('w',suffix='.cmd',delete=False,dir='.') as f:
        f.write(s+'\n'); n=f.name
    try:
        p=subprocess.run(['/home/jries/Develop/sdata/bin/sdata']+opts+[n],capture_output=True,text=True,errors='backslashreplace',timeout=30,stdin=subprocess.DEVNULL)
        out=(p.stdout+p.stderr); rc=p.returncode
    except subprocess.TimeoutExpired as e:
        out='TIMEOUT'; rc='T'
    os.unlink(n)
    flag=''
    if re.search(r'\.adb:|\.ads:|raised|CONSTRAINT|PROGRAM_ERROR|STORAGE_ERROR|Exception|exception|Segmentation|overflow check|range check|index check|length check|access check|divide',out) or rc not in (0,1):
        flag='  <<<<<< SUSPECT'
    print(f'--- #{i} rc={rc}{flag}')
    print(s[:300])
    print('>>>')
    print(out[:900].rstrip())
