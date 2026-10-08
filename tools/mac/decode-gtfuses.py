#!/usr/bin/env python3
"""decode-gtfuses.py [file] - print the GT fuse registers saved by patch 0003's igfxtglmap 0x80000 probe."""
import struct, sys
NAMES = {0x9138: 'GEN11_GT_SLICE_ENABLE', 0x913C: 'ICL SUBSLICE_DISABLE / TGL DSS_ENABLE', 0x9134: 'GEN11_EU_DISABLE', 0x9120: 'GEN8_FUSE2? (>>28 = "GPU Sku")',
         0x911C: '', 0x9118: '', 0x9140: 'GEN11_GT_VEBOX_VDBOX_DISABLE', 0x0D00: '', 0x9130: '', 0x9144: '', 0x9148: '', 0xA188: 'FORCEWAKE_GT', 0xA278: 'FORCEWAKE_RENDER',
         0x145948: '', 0x145994: '', 0x145998: 'RP caps?', 0x229C: 'RCS GFX_MODE', 0x7000: '', 0x7004: '', 0x7008: ''}
d = open(sys.argv[1] if len(sys.argv) > 1 else '/Users/Shared/tgl-gt-fuses.bin', 'rb').read()
magic, up, ab0, ab1, aa0, aa1, w0, w1 = struct.unpack_from('<8I', d, 0)
print('magic %08x  taken at %d s uptime' % (magic, up))
print('forcewake ack  render 0x0D84: %08x -> %08x (%d waits)   GT 0x130044: %08x -> %08x (%d waits)' % (ab0, aa0, w0, ab1, aa1, w1))
print('%-8s %-10s %-10s %s' % ('reg', 'plain', 'awake', ''))
vals = {}
for i in range((len(d) - 32) // 12):
    a, p, w = struct.unpack_from('<3I', d, 32 + 12 * i)
    vals[a] = w
    print('%06X   %08X   %08X   %s' % (a, p, w, NAMES.get(a, '')))
pc = lambda x: bin(x).count('1')
if 0x913C in vals:
    s, ss, eu, sku, vd = vals[0x9138], vals[0x913C], vals[0x9134], vals[0x9120] >> 28, (~vals[0x9140]) & 0xF00FF
    print('\nAs the Ice Lake accelerator would read them (approximate, see getGPUInfo):')
    print('  "GPU Sku" = %d   slice fuse = %#x   subslice fuse = %#x -> %d set, %d clear of 8   EU disable = %#x -> %d of 8 enabled   VD/VE = %#x' % (sku, s, ss, pc(ss & 0xFF), 8 - pc(ss & 0xFF), eu & 0xFF, 8 - pc(eu & 0xFF), vd))
