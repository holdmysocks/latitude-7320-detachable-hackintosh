#!/usr/bin/env python3
"""dis-icllp.py <mangled symbol or substring> [skip] [count]

Annotated disassembly of one function of AppleIntelICLLPGraphicsFramebuffer: register accessor calls are shortened to
READ32 / WRITE32, C++ names are demangled, and log strings referenced by the code are shown next to the instruction.
Expects ./icllp.bin (or $ICLLP_BIN), produced by extract_kext.py from SystemKernelExtensions.kc. The string section
addresses below are for macOS 26.6 (25G72), AppleIntelICLLPGraphicsFramebuffer 24.0.5.
"""
import os,subprocess,re,sys
BIN=os.environ.get('ICLLP_BIN','icllp.bin')
W=''
b=open(BIN,'rb').read()
def cstr(a):
    for vm,fo,sz in [(0x1405eec4,0x86ec4,0x1265a),(0x14071520,0x99520,0xede1)]:
        if vm<=a<vm+sz:
            o=fo+a-vm; e=b.find(b'\0',o); s=b[o:min(e,o+100)]
            return s.decode('latin-1').strip() if s and all(32<=x<127 or x==10 for x in s) else None
syms=[l.split()[2] for l in subprocess.run(['nm',BIN],capture_output=True,text=True).stdout.splitlines() if len(l.split())==3]
q=sys.argv[1]; cand=[s for s in syms if s==q] or [s for s in syms if q in s and '.cold' not in s]
sym=cand[0]; skip=int(sys.argv[2]) if len(sys.argv)>2 else 0; n=int(sys.argv[3]) if len(sys.argv)>3 else 400
out=subprocess.run(['objdump','-d','--no-show-raw-insn','--disassemble-symbols='+sym,BIN],capture_output=True,text=True).stdout.splitlines()[6:]
print("##",subprocess.run(['c++filt',sym],capture_output=True,text=True).stdout.strip(),len(out),"instructions")
def short(m):
    d=subprocess.run(['c++filt',m.group(1)],capture_output=True,text=True).stdout.strip().split('(')[0].replace('AppleIntelFramebufferController','AIFC')
    return '<'+d+(m.group(2) or '')+'>'
for l in out[skip:skip+n]:
    m=re.search(r'## 0x(140[0-9a-f]+)',l); extra=''
    if m:
        c=cstr(int(m.group(1),16)); extra=('   "'+c[:80]+'"') if c else ''
    l=l.replace('__ZN31AppleIntelFramebufferController14ReadRegister32Em','READ32').replace('__ZN31AppleIntelFramebufferController15WriteRegister32Emj','WRITE32')
    l=re.sub(r'<(__Z\w+?)(\+0x[0-9a-f]+)>',lambda m:'<'+m.group(2)+'>' if m.group(1)==sym else short(m),l)
    l=re.sub(r'<(__Z\w+)()>',short,l)
    l=re.sub(r'\s+## .*','',l)
    print(l.strip()[3:][:110]+extra)
