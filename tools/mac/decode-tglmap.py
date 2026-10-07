#!/usr/bin/env python3
"""decode-tglmap.py [file|-]  - decode the WhateverGreen 0003 `tgl-map-state` record.
Input: output of `nvram 4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:tgl-map-state`, or an ioreg line containing
"tgl-map-state" = <hex>, or plain hex. With no argument it reads both live sources itself."""
import struct, sys, subprocess, re
GUIDKEY = "4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:tgl-map-state"
FW = ["TRANS_DDI_FUNC_CTL_A", "TRANS_CLK_SEL_A", "TRANS_CONF_A", "DP_TP_CTL_A(TGL)", "DP_TP_STATUS_A(TGL)", "DDI_BUF_CTL_A", "DPLL0_ENABLE", "DPLL0_CFGCR0(TGL)",
      "DPLL0_CFGCR1(TGL)", "DPLL1_ENABLE", "DPLL1_CFGCR0(TGL)", "DPLL1_CFGCR1(TGL)", "DPCLKA_CFGCR0", "DSSM", "TRANS_HTOTAL_A", "TRANS_VTOTAL_A", "PIPE_SRCSZ?(6001C)",
      "PWR_WELL_CTL2", "PWR_WELL_CTL_AUX2", "PWR_WELL_CTL_DDI2", "CDCLK_CTL"]
MID = ["mappedReads", "mappedWrites", "tpEnables", "tpDisables", "synthClkSel", "synthFuncCtl", "lastTpCtl", "lastTpStatus", "orTpStatus", "lastFuncCtlAddr",
       "lastFuncCtlDriver", "lastFuncCtlOut", "lastConfAddr", "lastConf", "lastCfgcr0Addr", "lastCfgcr0Driver", "lastCfgcr0Out", "lastCfgcr1Addr", "lastCfgcr1Out",
       "lastDdiBufCtl", "lastDpll0Enable", "lastDpll1Enable", "lastDpclka", "lastClkSelOut"]
NOW = ["TRANS_DDI_FUNC_CTL_A", "TRANS_CLK_SEL_A", "TRANS_CONF_A", "DP_TP_CTL_A(TGL)", "DP_TP_STATUS_A(TGL)", "DDI_BUF_CTL_A", "DPLL0_ENABLE", "DPLL0_CFGCR0(TGL)",
       "DPLL1_ENABLE", "DPLL1_CFGCR0(TGL)", "DPCLKA_CFGCR0", "PP_STATUS", "PP_CONTROL", "BLC_PWM_CTL(C8250)"]
NAMES = {0x60400: "TRANS_DDI_FUNC_CTL_A", 0x46140: "TRANS_CLK_SEL_A", 0x70008: "TRANS_CONF_A", 0x60540: "DP_TP_CTL_A", 0x64000: "DDI_BUF_CTL_A", 0x46010: "DPLL0_ENABLE",
         0x46014: "DPLL1_ENABLE", 0x164284: "DPLL0_CFGCR0", 0x164288: "DPLL0_CFGCR1", 0x16428C: "DPLL1_CFGCR0", 0x164290: "DPLL1_CFGCR1", 0x164280: "DPCLKA_CFGCR0",
         0xC7204: "PP_CONTROL", 0x60000: "HTOTAL_A", 0x60004: "HBLANK_A", 0x60008: "HSYNC_A", 0x6000C: "VTOTAL_A", 0x60010: "VBLANK_A", 0x60014: "VSYNC_A",
         0x60030: "DATAM1_A", 0x60034: "DATAN1_A", 0x60040: "LINKM1_A", 0x60044: "LINKN1_A", 0x60410: "MSA_MISC_A", 0x60800: "PSR_CTL_A", 0x64010: "DDI_AUX_CTL_A",
         0x64014: "DDI_AUX_DATA_A"}
SNAP = ["TRANS_CONF_A", "TRANS_DDI_FUNC_CTL_A", "TRANS_CLK_SEL_A", "DP_TP_CTL_A", "DP_TP_STATUS_A", "DDI_BUF_CTL_A", "TRANS_HTOTAL_A", "TRANS_VTOTAL_A",
        "PIPE_SRCSZ_A", "DATAM1_A", "LINKM1_A", "PIPE_MISC_A", "PIPE_FRMCOUNT_A", "PIPE_SCANLINE_A", "PLANE_CTL_1_A", "PLANE_STRIDE_1_A",
        "PLANE_POS_1_A", "PLANE_SIZE_1_A", "PLANE_SURF_1_A", "PLANE_BUF_CFG_1_A", "PLANE_WM_0_1_A", "CUR_CTL_A", "CUR_BUF_CFG_A", "DBUF_CTL_S1",
        "DBUF_CTL_S2", "PWR_WELL_CTL2", "DC_STATE_EN", "DPLL0_ENABLE", "DPLL0_CFGCR0", "DPLL0_CFGCR1", "DPCLKA_CFGCR0", "PP_STATUS",
        "PP_CONTROL", "BLC_PWM_CTL (C8250)", "BLC_PWM_FREQ (C8254)", "BLC_PWM_DUTY (C8258)", "PSR_CTL_A", "PSR_STATUS_A", "DE_PIPE_ISR_A", "DE_PIPE_IMR_A",
        "0x6F400 (ICL eDP FUNC_CTL)", "0x7F008 (ICL eDP CONF)", "PF_CTL_A (68080)", "PIPE_MISC2_A", "GAMMA_MODE_A", "0x4A400", "CDCLK_CTL", "PIPE_FRMCOUNT_A (2nd read)"]
def notes(name, e, l):
    n = []
    if name == "TRANS_CONF_A": n.append("enable=%d state=%d" % (l >> 31, (l >> 30) & 1))
    if name == "TRANS_DDI_FUNC_CTL_A": n.append("enable=%d ddi_select=%d lanes=%d" % (l >> 31, (l >> 27) & 0xF, ((l >> 1) & 7) + 1))
    if name == "TRANS_CLK_SEL_A": n.append("ddi_select=%d" % ((l >> 28) & 0xF))
    if name == "DP_TP_CTL_A": n.append(tp(l))
    if name == "DDI_BUF_CTL_A": n.append("enable=%d idle=%d" % (l >> 31, (l >> 7) & 1))
    if name == "PLANE_CTL_1_A": n.append("enable=%d" % (l >> 31))
    if name == "PLANE_BUF_CFG_1_A": n.append("start=%d end=%d" % (l & 0x7FF, (l >> 16) & 0x7FF))
    if name == "PP_STATUS": n.append("panel_on=%d seq_state=%d" % (l >> 31, (l >> 28) & 3))
    if name == "PP_CONTROL": n.append("power_on=%d backlight_enable=%d vdd_override=%d" % (l & 1, (l >> 2) & 1, (l >> 3) & 1))
    if name.startswith("BLC_PWM_CTL"): n.append("pwm_enable=%d" % (l >> 31))
    if name == "DPLL0_ENABLE": n.append("enable=%d lock=%d power=%d" % (l >> 31, (l >> 30) & 1, (l >> 27) & 1))
    if name == "PSR_CTL_A": n.append("psr_enable=%d" % (l >> 31))
    if name == "PIPE_FRMCOUNT_A (2nd read)": n.append("frames advance between reads" if l != 0 else "")
    return "  ".join(x for x in n if x)

def from_nvram(text):
    v = text.split("\t", 1)[1].rstrip("\n") if "\t" in text else text.strip()
    out = bytearray(); i = 0
    while i < len(v):
        if v[i] == "%" and i + 2 < len(v) + 0 and re.fullmatch("[0-9a-fA-F]{2}", v[i+1:i+3] or ""):
            out.append(int(v[i+1:i+3], 16)); i += 3
        else:
            out.append(ord(v[i]) & 0xFF); i += 1
    return bytes(out)
def parse(text):
    m = re.search(r'"tgl-map-state" = <([0-9a-fA-F]+)>', text)
    if m: return bytes.fromhex(m.group(1))
    t = text.strip()
    if re.fullmatch("[0-9a-fA-F\\s]+", t) and len(t) > 64: return bytes.fromhex("".join(t.split()))
    return from_nvram(text)
def tp(v):
    pat = {0: "pattern1", 1: "pattern2", 2: "idle", 3: "NORMAL (trained)", 4: "pattern3", 5: "pattern4"}.get((v >> 8) & 7, "?")
    return "%s, %s" % ("enabled" if v >> 31 else "disabled", pat)
def show(b, title):
    print("=====", title, "(%d bytes)" % len(b))
    if len(b) < 8 or struct.unpack_from("<I", b, 0)[0] != 0x324D4754:
        print("  not a TGM2 record:", b[:16].hex()); return
    w = list(struct.unpack_from("<%dI" % (len(b) // 4), b, 0)); p = 1
    print("  publications (seq):", w[p]); p += 1
    print("  -- firmware state at the driver's first register access")
    for n in FW: print("     %-22s %08X" % (n, w[p])); p += 1
    print("  -- counters and last values")
    for n in MID:
        extra = ""
        if n == "lastTpCtl": extra = "   " + tp(w[p])
        if n in ("lastTpStatus", "orTpStatus"): extra = "   (bit25 idle done, bit26 active, bit12 min idles sent)"
        print("     %-22s %08X%s" % (n, w[p], extra)); p += 1
    print("  -- live registers at the last publication")
    for n in NOW:
        extra = "   " + tp(w[p]) if n.startswith("DP_TP_CTL") else ""
        print("     %-22s %08X%s" % (n, w[p], extra)); p += 1
    nxt = w[p]; p += 1; ring = [(w[p + 2*i], w[p + 2*i + 1]) for i in range(min(48, (len(w) - p) // 2))]
    n = len(ring); order = [ring[(nxt + i) % n] for i in range(n)] if nxt >= n else ring[:nxt]
    print("  -- last %d recorded writes, oldest first (T = translated or synthesized by the shim); total recorded %d" % (len(order), nxt))
    for a, v in order:
        addr = a & 0x7FFFFFFF
        print("     %s %06X %-22s = %08X%s" % ("T" if a >> 31 else " ", addr, NAMES.get(addr, ""), v, "   " + tp(v) if addr == 0x60540 else ""))
    q = p + 2 * n
    if len(w) >= q + 2 + 2 * len(SNAP):
        cnt, secs = w[q], w[q + 1]; early = w[q + 2:q + 2 + len(SNAP)]; late = w[q + 2 + len(SNAP):q + 2 + 2 * len(SNAP)]
        print("  -- hardware snapshots: %d late read(s); last publication %d s after the first DP_TP_CTL enable%s" % (cnt, secs, "  (stage 1 only: 'late' column is empty)" if cnt == 0 else ""))
        print("     %-28s %-10s %-10s %s" % ("register", "firmware", "late", "late decoded"))
        for i, name in enumerate(SNAP):
            print("     %-28s %08X   %08X   %s%s" % (name, early[i], late[i], "" if early[i] == late[i] else "* ", notes(name, early[i], late[i])))
def main():
    if len(sys.argv) > 1:
        raw = sys.stdin.buffer.read() if sys.argv[1] == "-" else open(sys.argv[1], "rb").read()
        if raw[:4] == b"TGM2": show(raw, sys.argv[1]); return
        show(parse(raw.decode("latin-1")), sys.argv[1]); return
    import os
    if os.path.exists("/Users/Shared/tgl-map-state.bin"):
        show(open("/Users/Shared/tgl-map-state.bin", "rb").read(), "/Users/Shared/tgl-map-state.bin (written by the shim's thread call)")
    else: print("file: no /Users/Shared/tgl-map-state.bin")
    r = subprocess.run(["nvram", GUIDKEY], capture_output=True)
    if r.returncode == 0: show(from_nvram(r.stdout.decode("latin-1")), "NVRAM (survives a dark boot; last publication of the boot that wrote it)")
    else: print("NVRAM: no", GUIDKEY)
    r = subprocess.run(["ioreg", "-l", "-w0"], capture_output=True, text=True, errors="replace")
    m = re.search(r'"tgl-map-state" = <[0-9a-fA-F]+>', r.stdout)
    if m: show(parse(m.group(0)), "IORegistry (this boot)")
    else: print("IORegistry: no tgl-map-state property (the shim is not active in this boot)")
if __name__ == "__main__": main()
