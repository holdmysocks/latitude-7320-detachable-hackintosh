#!/usr/bin/env python3
"""decode-tgltrace.py [file] [n] - print the last n entries of the on-disk register trace written by the 0003t build."""
import struct, sys
NAMES = {0xC8250: 'BLC_PWM_CTL', 0xC8254: 'BLC_PWM_FREQ', 0xC8258: 'BLC_PWM_DUTY', 0xC7200: 'PP_STATUS', 0xC7204: 'PP_CONTROL',
         0x70008: 'PIPEACONF', 0x7F008: 'PIPE_EDP_CONF', 0x60400: 'TRANS_DDI_FUNC_CTL_A', 0x6F400: 'TRANS_DDI_FUNC_CTL_EDP',
         0x64000: 'DDI_BUF_CTL_A', 0x64040: 'DP_TP_CTL_A(icl)', 0x64044: 'DP_TP_STATUS_A(icl)', 0x46140: 'TRANS_CLK_SEL_A',
         0x70180: 'PLANE_CTL_1_A', 0x7019C: 'PLANE_SURF_1_A', 0x70080: 'CUR_CTL_A', 0x70084: 'CUR_BASE_A', 0x70088: 'CUR_POS_A',
         0x45400: 'PWR_WELL_CTL1', 0x45404: 'PWR_WELL_CTL2', 0x45408: 'PWR_WELL_CTL3', 0x46000: 'CDCLK_CTL', 0x46070: 'CDCLK_PLL_ENABLE',
         0x46010: 'DPLL0_ENABLE', 0x164280: 'DPCLKA_CFGCR0', 0x70000: 'PIPE_SCANLINE_A', 0x70040: 'PIPE_FRMCNT_A', 0x44400: 'DE_PIPE_ISR_A',
         0x44404: 'DE_PIPE_IMR_A', 0x44408: 'DE_PIPE_IIR_A', 0x4440C: 'DE_PIPE_IER_A', 0x60800: 'PSR_CTL', 0x60840: 'PSR_STATUS',
         0x64010: 'AUX_CTL_A', 0x64014: 'AUX_DATA_A', 0x44200: 'MASTER_INT_CTL', 0x45010: 'DBUF_CTL', 0x4A000: 'LGC_PALETTE_A', 0x4A480: 'GAMMA_MODE_A'}
d = open(sys.argv[1] if len(sys.argv) > 1 else '/Users/Shared/tgl-trace.bin', 'rb').read()
n = int(sys.argv[2]) if len(sys.argv) > 2 else 80
magic, seq, nxt, by, flushes, timeouts, armup, nowup = struct.unpack_from('<8I', d, 0)
ring = (len(d) - 32) // 8
print('magic %08x seq %d entries %d armedBy %d flushes %d waitTimeouts %d armed at %d s, last flush at %d s' % (magic, seq, nxt, by, flushes, timeouts, armup, nowup))
have = min(nxt, ring, n)
for i in range(nxt - have, nxt):
    a, v = struct.unpack_from('<2I', d, 32 + 8 * (i % ring))
    w = a >> 31; a &= 0x7FFFFFFF
    if a & 0x40000000:
        print('%6d * hook marker %d: %s (%08X)' % (i, a & 0xF, {1: 'cleanup entered, TRANS_CONF_A after wait (0003o) / FUNC_CTL_A (0003t)', 2: 'FUNC_CTL select cleared, value = 100 us waits', 3: 'TRANS_CLK_SEL_A cleared', 4: 'returning to driver after DP_TP_CTL disable', 5: 'transcoder still running, clock left alone', 6: 'clock select left as is, value = TRANS_CLK_SEL_A', 7: 'port disabled, no clean-up (0003s)'}.get(a & 0xF, '?'), v)); continue
    print('%6d %s %06X %-22s %s' % (i, 'W' if w else 'r', a, NAMES.get(a, ''), ('%08X' % v) if w else ('x%d' % v)))
