#!/usr/bin/env python3
"""decode-tglhang.py [file] [outdir] - print /Users/Shared/tgl-hang.bin (igfxtglhang=1): what the render engine was
executing at each GPU hang. With outdir, also write the batch and the shader kernels as raw files."""
import struct, sys
path = sys.argv[1] if len(sys.argv) > 1 else '/Users/Shared/tgl-hang.bin'
out = sys.argv[2] if len(sys.argv) > 2 else None
b = open(path, 'rb').read()
SIZE = 392 + 12 * 4096
REGS = ['BB_ADDR', 'BB_ADDR_UDW', 'PDP0_LO', 'PDP0_HI', 'ACTHD', 'IPEHR', 'RING_HEAD', 'RING_TAIL', 'RING_START',
        'INSTDONE', 'GFX_MODE', 'R_PWR_CLK_STATE', 'CCID', 'EXECLIST_STATUS', 'SC_INSTDONE', 'EIR']
for n in range(len(b) // SIZE):
    r = b[n * SIZE:(n + 1) * SIZE]
    magic, ms = struct.unpack_from('<II', r, 0)
    if magic != 0x41484754: print('record %d: bad magic 0x%08X' % (n, magic)); continue
    reg = struct.unpack_from('<16I', r, 8)
    pml4, page = struct.unpack_from('<QQ', r, 72)
    phys = struct.unpack_from('<8Q', r, 88)
    iba, sba_at = struct.unpack_from('<QQ', r, 152)
    kat = struct.unpack_from('<2Q', r, 168); kphys = struct.unpack_from('<2Q', r, 184)
    kcmd = [struct.unpack_from('<12I', r, 200 + 48 * k) for k in range(2)]
    sba = struct.unpack_from('<22I', r, 296)
    batch = r[392:392 + 8 * 4096]; kern = [r[392 + (8 + 2 * k) * 4096:392 + (10 + 2 * k) * 4096] for k in range(2)]
    print('== hang %d at %.3f s' % (n, ms / 1000))
    print('  ' + '  '.join('%s=%08X' % (REGS[i], reg[i]) for i in range(8)))
    print('  ' + '  '.join('%s=%08X' % (REGS[i], reg[i]) for i in range(8, 16)))
    print('  page table %X   batch pages (GPU %X .. %X) mapped: %s' % (pml4, page - 7 * 4096, page, ' '.join('y' if p else '-' for p in phys)))
    print('  STATE_BASE_ADDRESS at %X: %s' % (sba_at, ' '.join('%08X' % w for w in sba)) if sba_at else '  STATE_BASE_ADDRESS not found')
    print('  instruction base %X' % iba)
    for k, name in enumerate(('3DSTATE_VS', '3DSTATE_PS')):
        if not kat[k]: print('  %s not found' % name); continue
        print('  %s: %s' % (name, ' '.join('%08X' % w for w in kcmd[k])))
        print('    kernel at GPU %X (physical %X), first 16 instructions (16 bytes each if not compacted):' % (kat[k], kphys[k]))
        o = kat[k] & 0xFFF
        for i in range(16):
            w = struct.unpack_from('<4I', kern[k], o + 16 * i)
            print('      %04X: %08X %08X %08X %08X' % (16 * i, *w))
        if out: open('%s/hang%d-%s.bin' % (out, n, name[8:].lower()), 'wb').write(kern[k][o:])
    if out: open('%s/hang%d-batch.bin' % (out, n), 'wb').write(batch)
    off = (7 * 4096 + (reg[0] & 0xFFF)) // 4 * 4
    print('  last 24 dwords of the batch before BB_ADDR:')
    ws = struct.unpack_from('<24I', batch, max(0, off - 96))
    for i in range(0, 24, 8): print('    ' + ' '.join('%08X' % w for w in ws[i:i + 8]))
