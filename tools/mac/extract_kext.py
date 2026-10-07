#!/usr/bin/env python3
"""extract_kext.py <kernel collection> <bundle id> <out>  - copy one fileset entry into a standalone, inspect-only Mach-O."""
import struct, sys
kc = open(sys.argv[1],'rb').read(); want = sys.argv[2]; out = sys.argv[3]
magic, cputype, cpusub, filetype, ncmds, sizeofcmds, flags, reserved = struct.unpack_from('<IiiIIIII', kc, 0)
assert magic == 0xfeedfacf and filetype == 0xc
off = 32; entry = None
for i in range(ncmds):
    cmd, size = struct.unpack_from('<II', kc, off)
    if cmd == 0x80000035:
        vmaddr, fileoff, strofs = struct.unpack_from('<QQI', kc, off+8)
        if kc[off+strofs:kc.index(b'\0', off+strofs)].decode() == want: entry = fileoff
    off += size
assert entry is not None, 'entry not found'
magic, cputype, cpusub, filetype, ncmds, sizeofcmds, flags, reserved = struct.unpack_from('<IiiIIIII', kc, entry)
segs = []; symtab = None; off = entry + 32
for i in range(ncmds):
    cmd, size = struct.unpack_from('<II', kc, off)
    if cmd == 0x19:
        name = kc[off+8:off+24].rstrip(b'\0').decode()
        vmaddr, vmsize, fileoff, filesize, maxprot, initprot, nsects, sflags = struct.unpack_from('<QQQQiiII', kc, off+24)
        secs = []; so = off + 72
        for s in range(nsects):
            sn = kc[so:so+16]; sg = kc[so+16:so+32]
            addr, ssize, soff, align, reloff, nreloc, sfl, r1, r2, r3 = struct.unpack_from('<QQIIIIIIII', kc, so+32)
            secs.append((sn, sg, addr, ssize, soff, align, sfl)); so += 80
        if name != '__LINKEDIT': segs.append((name, vmaddr, vmsize, fileoff, filesize, maxprot, initprot, sflags, secs))
    elif cmd == 0x2: symtab = struct.unpack_from('<IIII', kc, off+8)
    off += size
hdr_size = 32 + sum(72 + 80*len(s[8]) for s in segs) + 72 + 24
pos = (hdr_size + 0xfff) & ~0xfff; lcs = b''; blobs = []
for name, vmaddr, vmsize, fileoff, filesize, maxprot, initprot, sflags, secs in segs:
    newoff = pos if filesize else 0
    lc = struct.pack('<II16sQQQQiiII', 0x19, 72+80*len(secs), name.encode().ljust(16,b'\0'), vmaddr, vmsize, newoff, filesize, maxprot, initprot, len(secs), sflags)
    for sn, sg, addr, ssize, soff, align, sfl in secs:
        lc += struct.pack('<16s16sQQIIIIIIII', sn, sg, addr, ssize, (newoff + soff - fileoff) if soff else 0, align, 0, 0, sfl, 0, 0, 0)
    lcs += lc
    if filesize: blobs.append((pos, kc[fileoff:fileoff+filesize])); pos = (pos + filesize + 0xfff) & ~0xfff
symoff, nsyms, stroff, strsize = symtab
newstr = bytearray(b'\0'); newnl = bytearray()
for i in range(nsyms):
    n_strx, n_type, n_sect, n_desc, n_value = struct.unpack_from('<IBBHQ', kc, symoff + i*16)
    nm = kc[stroff+n_strx:kc.index(b'\0', stroff+n_strx)]
    newnl += struct.pack('<IBBHQ', len(newstr), n_type, n_sect, n_desc, n_value); newstr += nm + b'\0'
le = bytes(newnl) + bytes(newstr)
lcs += struct.pack('<II16sQQQQiiII', 0x19, 72, b'__LINKEDIT'.ljust(16,b'\0'), 0, len(le), pos, len(le), 7, 1, 0, 0)
lcs += struct.pack('<IIIIII', 0x2, 24, pos, nsyms, pos+len(newnl), len(newstr))
o = bytearray(pos + len(le)); h = struct.pack('<IiiIIIII', 0xfeedfacf, cputype, cpusub, 0xb, len(segs)+2, len(lcs), 0, 0)
o[0:32] = h; o[32:32+len(lcs)] = lcs
for p, d in blobs: o[p:p+len(d)] = d
o[pos:pos+len(le)] = le; open(out,'wb').write(o); print('wrote', out, len(o), 'symbols', nsyms)
