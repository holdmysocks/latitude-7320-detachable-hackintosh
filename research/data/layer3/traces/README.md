# Register traces of the display sleep freeze

Written by patch 0003's on-disk trace (`igfxtglmap` `0x10000`) on 2026-10-07/08; `.txt` is the output of
`tools/mac/decode-tgltrace.py`. Each file is what was on disk after the machine froze and was powered off.
`W` = register write by Apple's driver (value before translation), `r` = reads (count), `*` = a marker written by
the patch's own code.

| File | Build | `dc6config=0` | Trace mode | Brightness | Last entry |
|---|---|---|---|---|---|
| `freeze-1` | 0003t | no | blocking | 100 % | driver's `DP_TP_CTL_A = 0x00040300` (no markers in this build) |
| `freeze-2` | 0003t | no | blocking | 90 % | same |
| `freeze-3` | 0003t rev 2 | no | blocking | 100 % | marker 2, after the patch cleared the DDI select in `TRANS_DDI_FUNC_CTL_A` |
| `freeze-4` | 0003o (waits for the transcoder to stop) | no | blocking | 100 % | marker 2; marker 1 shows `TRANS_CONF_A = 0x24` (off) |
| `freeze-5` | 0003p (no `TRANS_CLK_SEL_A` write) | no | blocking | 100 % | marker 2 |
| `freeze-6` | 0003r | yes | no-wait (`0x40000`) | 100 % | marker 2, at full driver speed |

The revision that removed the clean-up entirely (0003s) did not freeze. Account: [`../../../LAYER3.md`](../../../LAYER3.md#7-the-display-sleep-freeze).
