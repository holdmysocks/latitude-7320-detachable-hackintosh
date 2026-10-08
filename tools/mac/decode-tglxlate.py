#!/usr/bin/env python3
"""decode-tglxlate.py [file] [outdir] - print /Users/Shared/tgl-xlate.bin (igfxtglxl=1): what the shader translator
did. With outdir, also write the first rejected kernels as raw files (feed them to g11to12 dis11)."""
import struct, sys
path = sys.argv[1] if len(sys.argv) > 1 else '/Users/Shared/tgl-xlate.bin'
out = sys.argv[2] if len(sys.argv) > 2 else None
b = open(path, 'rb').read()
names = ['magic', 'hooked', 'nowMs', 'batches', 'walked', 'notRender', 'badImage', 'noEnd', 'commands', 'kernelRefs',
         'translated', 'cacheHits', 'rejected', 'rejectedAgain', 'unmapped', 'noBase', 'bytesOut', 'nfails', 'nsamples', 'empty']
v = dict(zip(names, struct.unpack_from('<20I', b, 0)))
SAMPLE = 1024 if len(b) < 20000 else 4096          # the first build kept 1 KB of each rejected kernel
HDR = len(b) - 24 * 128 - 6 * SAMPLE   # 80; 88 with the stolen memory range; 96 with the resolve counters
if HDR >= 88: v['stolenBase'], v['stolenSize'] = struct.unpack_from('<2I', b, 80)
if v['magic'] != 0x4C584754: sys.exit('not a tgl-xlate record (magic 0x%08X)' % v['magic'])
print('hook           :', {0: 'not attempted', 1: 'routed', 2: 'a symbol was missing', 3: 'routing failed'}.get(v['hooked'], v['hooked']))
print('written at     : %.3f s uptime' % (v['nowMs'] / 1000))
print('batches        : %(batches)d submitted, %(walked)d walked, %(notRender)d other engines, %(badImage)d unreadable context image, %(noEnd)d walks without an end' % v)
print('commands       : %(commands)d' % v)
if HDR >= 96: print('resolves skipped: %d colour, %d depth (igfxtglres)' % struct.unpack_from('<2I', b, 88))
if 'stolenBase' in v: print('stolen memory  : %d MB at 0x%X (never read or written)' % (v['stolenSize'], v['stolenBase'] << 20))
print('kernel pointers: %(kernelRefs)d  ->  %(translated)d translated (%(bytesOut)d bytes), %(cacheHits)d already translated, %(rejected)d rejected, %(rejectedAgain)d rejected before, %(unmapped)d unmapped, %(noBase)d without a base address, %(empty)d empty' % v)
STAGE = {0x7810: 'VS', 0x781B: 'HS', 0x781D: 'DS', 0x7811: 'GS', 0x7820: 'PS'}
for i in range(min(v['nfails'], 24)):
    ms, cmd, off, n, at = struct.unpack_from('<IIIIQ', b, HDR + 128 * i)
    reason = b[HDR + 128 * i + 24:HDR + 128 * i + 80].split(b'\0')[0].decode(errors='replace')
    raw = b[HDR + 128 * i + 80:HDR + 128 * i + 128]
    print('  rejected %2d  %7d ms  %s kernel at %X: "%s" at +0x%X (%d instructions before the end of the walk)' % (i, ms, STAGE.get(cmd >> 16, '%08X' % cmd), at, reason, off, n))
    print('               ' + ' '.join('%08X' % w for w in struct.unpack_from('<8I', raw, 0)))
for i in range(min(v['nsamples'], 6)):
    s = b[HDR + 24 * 128 + SAMPLE * i:HDR + 24 * 128 + SAMPLE * (i + 1)]
    if out: open('%s/rejected%d.bin' % (out, i), 'wb').write(s)
if out and v['nsamples']: print('wrote %d rejected kernels to %s' % (min(v['nsamples'], 6), out))
