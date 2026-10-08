#!/usr/bin/env python3
"""decode-tglcsb.py [file] - print /Users/Shared/tgl-csb.bin, the context status buffer log of the igfxtglcsb reader."""
import struct, sys
path = sys.argv[1] if len(sys.argv) > 1 else '/Users/Shared/tgl-csb.bin'
b = open(path, 'rb').read()
magic, hooked, used, flushes, now_ms, accel_flags, calls, _ = struct.unpack_from('<8I', b, 0)
if magic != 0x53434754: sys.exit('not a tgl-csb record (magic 0x%08X)' % magic)
counts = struct.unpack_from('<8I', b, 32)
print('hook        :', {0: 'not attempted', 1: 'routed', 2: 'a handler symbol was missing', 3: 'routing failed'}.get(hooked, hooked))
print('written at  : %.3f s uptime, flush %d' % (now_ms / 1000, flushes))
print('calls       : %d   accelerator flags 0x%08X (bit 7 = MMIO mode)' % (calls, accel_flags))
print('events      : handed on %d, skipped %d, both idle %d, not written %d, passthrough %d, bad pointer %d, after reset %d'
      % counts[:7])
NAMES = {1: 'idle->active', 2: 'preempted', 3: 'element switch', 4: 'active->idle', 0x20: 'BOTH IDLE', 0x30: 'NOT WRITTEN',
         0x40: 'passthrough', 0x50: 'BAD POINTER', 0x60: 'after reset'}
ENG = {0: 'RCS', 1: 'VCS0', 2: 'BCS', 3: 'VCS2', 4: 'VECS'}
def ident(v): return '-' if v == 0xFFFF else '?' if v == 0xFFFE else '%X' % v
print('records     : %d\n' % min(used, 2040))
print('    ms  eng  idx wp  lo        hi        to   away det  action             synth  active   pending  flags')
for i in range(min(used, 2040)):
    ms, eng, act, idx, wp, lo, hi, synth, a0, a1, p0, p1, flags = struct.unpack_from('<IBBBBIIIHHHHI', b, 64 + 32 * i)
    name = ('SKIPPED ' + NAMES.get(act & 0xF, '?')) if act & 0xF0 == 0x10 else NAMES.get(act, '0x%X' % act)
    to, away = (lo >> 15) & 0x7FF, (hi >> 15) & 0x7FF
    print('%6d  %-4s %2d %2d  %08X  %08X  %-4s %-4s %X    %-18s %04X   %-3s %-3s  %-3s %-3s  %X'
          % (ms, ENG.get(eng, eng), idx, wp, lo, hi, 'idle' if to == 0x7FF else '%X' % to, 'idle' if away == 0x7FF else '%X' % away,
             hi & 0xF, name, synth, ident(a0), ident(a1), ident(p0), ident(p1), flags))
