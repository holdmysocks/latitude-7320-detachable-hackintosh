#!/usr/bin/env python3
"""Build an OpenCore experiment config from the known-good config (never modified).

Usage: make-experiment.py <known-good.plist> <out.plist> <experiment> [--dvmt-mb=N] [--plat=HEX] [--dev=HEX]

Config-only experiments (stock-behaving WhateverGreen, no rebuild needed):
  A         WhateverGreen in Ice Lake mode (lilucpu=12), DVMT fix (-igfxdvmt), CD clock fix (-igfxcdc),
            device-id 8A5A, AAPL,ig-platform-id 0x8A5C0002 (the Lenovo 9A78 recipe), accelerator excluded.
  A-sam     A with Samsung's pair: device-id 8A71, platform 0x8A710000 (Camellia disabled, 6 ports).
  A-cam0    A with device-id 8A5C, platform 0x8A5C0000 (Camellia disabled, 6 ports).
  A-nocdc   A without -igfxcdc.
  A-static  A, but the DVMT value is hard-coded by a static OpenCore patch (--dvmt-mb, default 60)
            instead of WhateverGreen's -igfxdvmt. Use when the WG build in use cannot run the fix.

Register-map experiments (need the 0003b WhateverGreen build on the ESP). igfxtglmap=<mask>:
0x01 eDP transcoder block -> transcoder A, 0x02 DP_TP_CTL/STATUS, 0x04 TRANS_DDI_FUNC_CTL select, 0x08 TRANS_CLK_SEL,
0x10 DPLL config, 0x20 synthesized pre-enable writes, 0x40 state to IORegistry, 0x80 state to NVRAM, 0x100 IOLog.
  C         A + igfxtglmap=0x3E: every translation except the eDP transcoder block, no side effects.
            The driver keeps the startup path that survived in run A; link training, clock select and PLL
            go to the Tiger Lake registers; the transcoder itself stays as the firmware left it.
  D         A + igfxtglmap=0x43F: every translation, eDP reads mapped only after the driver first programs
            the eDP transcoder (0x400), no side effects. Startup as in runs A and C, full mapping from the
            first modeset on, so the transcoder is really stopped and restarted around link training.
  D-fwpll   D + -igfxtglfwpll.
  E         A + igfxtglmap=0xC3F: D, but only the eDP registers the video stream needs are mapped (timings, M/N,
            TRANS_DDI_FUNC_CTL, MSA, TRANS_CONF). PSR, VRR and DIP registers stay unmapped as in runs A and C.
  E-dc6     E + dc6config=0 (the driver's own switch: no DMC firmware upload, no DC6).
  E-fwpll   E + -igfxtglfwpll.
  F         A + igfxtglmap=0x3E on the 0003e build: run C plus the TRANS_CLK_SEL fix (the driver writes 0 to
            TRANS_CLK_SEL of the pipe right after eDP link training; 0003e keeps DDI A selected). The eDP block
            stays unmapped, so the driver never waits on the transcoder and cannot freeze there.
  G         A + igfxtglmap=0xC3F on the 0003e build: run E plus the same fix (transcoder properly reprogrammed).
  F-fwpll / G-fwpll / G-dc6   as before.
  F2        F + -igfxblr -igfxdbeo: WhateverGreen's stock Ice Lake fixes for a dark backlight (PWM frequency/duty
            rescaling) and for the display data buffer allocation (underruns, "Failed to distribute DBufs").
  F2-blr / F2-dbeo   F plus only one of the two.
  G2        G + -igfxblr -igfxdbeo.
  F3        F2 + 0x2000 (igfxtglmap=0x203E) on the 0003f build: delayed hardware snapshot to NVRAM. WAIT 4 MINUTES
            before powering off a dark boot (snapshots at 60 s and 180 s after the modeset).
  G3        G2 + 0x2000 (igfxtglmap=0x2C3F).
  K         A + igfxtglmap=0x603E -igfxdbeo on the 0003i build: F plus the backlight guard (0x4000: keep the firmware's
            PWM frequency and duty) and the file snapshot (0x2000). No -igfxblr (it would bypass the guard).
  K-min     A + igfxtglmap=0x403E: F plus only the backlight guard.
  M         Brightness attempt on the 0003j build: igfxtglmap=0xA83F -igfxdbeo and SSDT-PNLF enabled.
            0x01|0x800 maps the eDP stream registers from the start (panel should land on the built-in connector, FB0),
            0x8000 rescales the backlight duty instead of pinning it, 0x2000 keeps the file snapshot.
  N         M + BrightnessKeys.kext in Kernel/Add (must be in EFI/OC/Kexts) on the 0003k build.
  P         N + SSDT-DOSI.aml in ACPI/Add (must be in EFI/OC/ACPI): presets the Dell firmware's OS identity to "Vista" on
            macOS so that it forwards brightness key events (Notify LCD 0x86/0x87) to BrightnessKeys.kext.
  P2        P with SSDT-DOSI revision 2 (OS identity set at table load, STOS repeated). Brightness keys work.
  Q         P2 on the 0003l build with SSDT-PNLF _UID 15 and igfxtglblmax=0xAD9: full brightness without _UID 19,
            which freezes the machine when the display powers off.
  R         Q + dc6config=0 (the driver skips its Ice Lake DMC firmware and hardware DC6). Without it the machine
            hard-freezes a few ms after the display engine goes idle at display sleep.
  S         R with igfxtglmap=0x2A83F on the 0003q build: the display power-down is paced (2 ms between register writes).
  GA1      first accelerator probe: R without the Kernel/Block entry for AppleIntelICLGraphics, plus the accelerator's
            own boot-args -allow3d (it refuses PCI revision <= 2 otherwise) and -disablegfxfirmware. Expected to panic in
            IntelAccelerator::getGPUInfo ("Unsupported ICL Sku") or hang; the [IGPU] HWCAPS log lines are the point.
  GA2       GA1 + igfxtglss=6 (0003x build patches the accelerator at load): getGPUInfo takes NumSubSlices = 6, which with this chip's "GPU Sku" fuse value 9 is the
            driver's "ICL 1x6x8 LP" case, instead of computing 27 from the Tiger Lake fuse and panicking.
  GA3       GA2 + igfxtglcsb=1 (0003y build): the accelerator's context status buffer is read in the Tiger Lake (Gen12)
            layout and handed to the driver's handlers as Ice Lake entries; every event is logged to
            /Users/Shared/tgl-csb.bin (decode-tglcsb.py). The log file stays open: power off by hand afterwards.
  GA4       GA3's configuration on the 0003z build: the reader wraps after 6 entries (GA3 showed the hardware does;
            0003y assumed 12 and stalled at entry 6, black login screen).
  GA5       GA4 with igfxtglss=4 instead of 6: GA4's GPU hang reports show the vertex shader stage busy and the driver's
            "subslice 5" absent (the chip has 5 dual subslices). The driver may log or reject Sku 9 with 4 subslices.
  GA6       GA4 + igfxtglhang=1 (0004a build): at each of the first three GPU hangs the hung batch and the vertex and
            pixel shader kernels it points to are written to /Users/Shared/tgl-hang.bin (decode-tglhang.py).
  GA7       GA6 + igfxtglxl=1 (0004b build): shader kernels are translated from Gen11 to Gen12 EU code in place when a
            batch is submitted. Statistics and rejected kernels: /Users/Shared/tgl-xlate.bin (decode-tglxlate.py).
  GA8       GA7's configuration on the 0004c build: the translator also handles sends that depend on each other (inserted
            sync), branches and loops, instructions without a Gen12 compact form, and more accumulator cases.
  GA9       GA7's configuration on the 0004d build: register usage tracked exactly (GA8 rejected one 16-wide pixel shader
            for lack of a free register, and the GPU hung in the batch that used it).
  GA10      GA7's configuration on the 0004e build: the translator also handles jmpi, descriptors taken from a register,
            and kernels up to 36 KB (GA9 drew for the first time and still rejected 145 shaders of those kinds).
  GA11      GA7's configuration on the 0004f build. GA10 ended in a machine check: the kext read the GPU's placeholder
            page in stolen memory. 0004f only touches RAM, and the translator covers goto/join, register-indirect
            addressing, zero padding inside a kernel, acc1 destinations and kernels up to 100 KB.
  GA12      GA11 + igfxtglres=3 on the 0004g build: shaders up to 700 KB are translated (GA11 rejected a 340 KB image-
            processing shader), unused pixel-shader kernel pointers are ignored, and the driver's own colour and depth
            resolve submissions are skipped (GA11 hung in a fast-clear batch built for Ice Lake).
  M-fb      igfxtglmap=0x683F -igfxdbeo: only the eDP mapping change relative to K (backlight still pinned, no PNLF).
  M-pnlf    K's mask with 0x8000 instead of 0x4000 (0xA03E) and SSDT-PNLF enabled: no eDP mapping change.
  F5        Same arguments as F3, on the 0003h build: the snapshot goes to /Users/Shared/tgl-map-state.bin in three
            stages (45 s: firmware snapshot only; 75 s and 180 s: fresh register reads). WAIT 4 MINUTES.
  F4        Same arguments as F3, on the 0003g build (snapshot published from a kernel thread call instead of from
            inside the register hook, which reset the machine in run F3). WAIT 4 MINUTES before powering off.
  B         A + igfxtglmap=0x3F: every translation, no side effects.
  B-state   A + igfxtglmap=0xFF: B plus the state record (what run B effectively was; it reset).
  C-fwpll / B-fwpll   add -igfxtglfwpll (keep the firmware's PLL configuration).
  H         A + igfxtglmap=0x200: hooks installed, nothing translated (isolates the write hook itself).

Tracer experiments (need the patched 0001/0002 WhateverGreen on the ESP; -igfxtgl, TigerLake detection).
They all carry the static DVMT patch (so the stolen-memory bug is out of the picture), a platform id that
exists in Tahoe's table, and the accelerator exclusion:
  selftest  0002: -igfxtgl -igfxtglselftest, -igfxvesa KEPT, device-id only (safe; expects a panic)
  alive     0002: -igfxtgl -igfxtglalive,    -igfxvesa KEPT, device-id only (safe; expects a panic)
  stop=N    0001/0002: -igfxtgl igfxtglstop=N, platform injected, no -igfxvesa (can reset)
  fn=N      0002: -igfxtgl igfxtglfn=N (panic on entry to function N of 27)      (can reset)
  fnret=N   0002: -igfxtgl igfxtglfnret=N (panic after function N returns)       (can reset)
  revert    Copy of the known-good config.
Options: --dvmt-mb=60 (static patch value; 60 = GMS 0xFE, the Tiger Lake firmware default)
         --plat=8A5C0002 --dev=8A5A override the injected ids for any experiment.
"""
import plistlib, sys, struct

IGPU = "PciRoot(0x0)/Pci(0x2,0x0)"
ACCEL = 'com.apple.driver.AppleIntelICLGraphics'
FB = 'com.apple.driver.AppleIntelICLLPGraphicsFramebuffer'
# IDs present in Tahoe 26.6 (25G72) AppleIntelICLLPGraphicsFramebuffer (from __GLOBAL__sub_I_AppleIntelOSInfoList.cpp)
TAHOE_IDS = {0x8A510000, 0x8A510001, 0x8A510002, 0x8A520001, 0x8A520002, 0x8A530001, 0x8A530002, 0x8A5A0001,
             0x8A5B0001, 0x8A5C0000, 0x8A5C0001, 0x8A5C0002, 0x8A5D0000, 0x8A5D0001, 0x8A700000, 0x8A700001,
             0x8A710000, 0x8A710001, 0xFF050000}
MATCH_IDS = {0xFF05, 0x8A70, 0x8A71, 0x8A51, 0x8A5C, 0x8A5D, 0x8A52, 0x8A53, 0x8A5A, 0x8A5B}

def le32(v): return struct.pack('<I', v)

def accel_subslice_patch(count):
    """IntelAccelerator::getGPUInfo: NumSubSlices = popcount(~fuse 0x913C). On Tiger Lake that register is the dual-
    subslice ENABLE mask (0x1F here), so the driver computes 27 and panics with "Unsupported ICL Sku". Force a count."""
    return {'Arch': 'x86_64', 'Base': '', 'Comment': 'AppleIntelICLGraphics getGPUInfo: NumSubSlices = %d' % count, 'Count': 1,
            'Enabled': True, 'Find': bytes.fromhex('4489F8F7D0F30FB8F089B388110000'), 'Identifier': ACCEL, 'Limit': 0,
            'Mask': b'', 'MaxKernel': '', 'MinKernel': '',
            'Replace': bytes.fromhex('4489F8BE%02X0000009089B388110000' % count), 'ReplaceMask': b'', 'Skip': 0}

def static_dvmt_patch(mb):
    # FBMemMgr_Init, macOS 26.6: shll $0x11,%eax; andl $0xFE000000,%eax; movl %eax,0xd9c(%rbx)
    find = bytes.fromhex('C1E01125000000FE' '89839C0D0000')
    repl = b'\xB8' + le32(mb << 20) + b'\x90\x90\x90' + bytes.fromhex('89839C0D0000')
    assert len(find) == len(repl) == 14
    return {'Arch': 'x86_64', 'Base': '__ZN31AppleIntelFramebufferController13FBMemMgr_InitEv',
            'Comment': 'TGL experiment: DVMT pre-alloc = %d MB (Apple formula misreads GMS 0xF0-0xFE as GMS*32MB)' % mb,
            'Count': 1, 'Enabled': True, 'Find': find, 'Identifier': FB, 'Limit': 0, 'Mask': b'',
            'MaxKernel': '', 'MinKernel': '', 'Replace': repl, 'ReplaceMask': b'', 'Skip': 0}

def block_accel():
    return {'Arch': 'x86_64', 'Comment': 'TGL experiment: framebuffer only, keep the Ice Lake accelerator out',
            'Enabled': True, 'Identifier': ACCEL, 'MaxKernel': '', 'MinKernel': '', 'Strategy': 'Exclude'}

def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    opts = dict((a[2:].split('=', 1) if '=' in a else (a[2:], '')) for a in sys.argv[1:] if a.startswith('--'))
    if len(args) != 3:
        print(__doc__); sys.exit(2)
    src, dst, exp = args
    dvmt_mb = int(opts.get('dvmt-mb', '60'))
    with open(src, 'rb') as f:
        p = plistlib.load(f)
    nv = p['NVRAM']['Add']['7C436110-AB2A-4BBB-A880-FE41995C9F82']
    base_args = nv['boot-args']
    if '-igfxvesa' not in base_args:
        sys.exit("refusing: source config does not look like the known-good (no -igfxvesa in boot-args)")
    if IGPU in p['DeviceProperties']['Add']:
        sys.exit("refusing: source config already has an IGPU DeviceProperties entry")

    dev, plat = 0x8A5A, 0x8A5C0002
    if exp == 'A-sam':  dev, plat = 0x8A71, 0x8A710000
    if exp == 'A-cam0': dev, plat = 0x8A5C, 0x8A5C0000
    if 'dev' in opts:  dev = int(opts['dev'], 16)
    if 'plat' in opts: plat = int(opts['plat'], 16)
    if dev not in MATCH_IDS: sys.exit("device-id %04X is not in the framebuffer's IOPCIPrimaryMatch" % dev)
    if plat not in TAHOE_IDS: sys.exit("platform id %08X is not in Tahoe's framebuffer table" % plat)

    keep_vesa, with_plat, extra, static = False, True, [], False
    if exp == 'revert':
        pass
    elif exp.startswith('A'):
        extra = ["lilucpu=12", "-igfxdvmt", "-igfxcdc"]
        if exp == 'A-nocdc': extra.remove("-igfxcdc")
        if exp == 'A-static': extra.remove("-igfxdvmt"); static = True
        if exp not in ('A', 'A-sam', 'A-cam0', 'A-nocdc', 'A-static'): sys.exit("unknown experiment %r" % exp)
    elif exp in ('B', 'B-fwpll', 'B-state', 'C', 'C-fwpll', 'D', 'D-fwpll', 'E', 'E-fwpll', 'E-dc6', 'F', 'F-fwpll', 'F2', 'F2-blr', 'F2-dbeo', 'F3', 'F4', 'F5', 'K', 'K-min', 'M', 'N', 'P', 'P2', 'Q', 'R', 'S', 'GA1', 'GA2', 'GA3', 'GA4', 'GA5', 'GA6', 'GA7', 'GA8', 'GA9', 'GA10', 'GA11', 'GA12', 'M-fb', 'M-pnlf', 'G', 'G-fwpll', 'G-dc6', 'G2', 'G3', 'H'):
        mask = {'B': 0x3F, 'B-fwpll': 0x3F, 'B-state': 0xFF, 'C': 0x3E, 'C-fwpll': 0x3E, 'D': 0x43F, 'D-fwpll': 0x43F, 'E': 0xC3F, 'E-fwpll': 0xC3F, 'E-dc6': 0xC3F, 'F': 0x3E, 'F-fwpll': 0x3E, 'F2': 0x3E, 'F2-blr': 0x3E, 'F2-dbeo': 0x3E, 'F3': 0x203E, 'F4': 0x203E, 'F5': 0x203E, 'K': 0x603E, 'K-min': 0x403E, 'M': 0xA83F, 'N': 0xA83F, 'P': 0xA83F, 'P2': 0xA83F, 'Q': 0xA83F, 'R': 0xA83F, 'S': 0x2A83F, 'GA1': 0xA83F, 'GA2': 0xA83F, 'GA3': 0xA83F, 'GA4': 0xA83F, 'GA5': 0xA83F, 'GA6': 0xA83F, 'GA7': 0xA83F, 'GA8': 0xA83F, 'GA9': 0xA83F, 'GA10': 0xA83F, 'GA11': 0xA83F, 'GA12': 0xA83F, 'M-fb': 0x683F, 'M-pnlf': 0xA03E, 'G3': 0x2C3F, 'G2': 0xC3F, 'G': 0xC3F, 'G-fwpll': 0xC3F, 'G-dc6': 0xC3F, 'H': 0x200}[exp]
        extra = ["lilucpu=12", "-igfxdvmt", "-igfxcdc", "igfxtglmap=0x%X" % mask]
        if exp.endswith('-fwpll'): extra.append("-igfxtglfwpll")
        if exp in ('Q', 'R', 'S', 'GA1', 'GA2', 'GA3', 'GA4', 'GA5', 'GA6', 'GA7', 'GA8', 'GA9', 'GA10', 'GA11', 'GA12'): extra.append("igfxtglblmax=0xAD9")
        if exp.endswith('-dc6') or exp in ('R', 'S', 'GA1', 'GA2', 'GA3', 'GA4', 'GA5', 'GA6', 'GA7', 'GA8', 'GA9', 'GA10', 'GA11', 'GA12'): extra.append("dc6config=0")
        if exp in ('F2', 'G2', 'F2-blr', 'F3', 'F4', 'F5', 'G3'): extra.append("-igfxblr")
        if exp in ('F2', 'G2', 'F2-dbeo', 'F3', 'F4', 'F5', 'K', 'M', 'N', 'P', 'P2', 'Q', 'R', 'S', 'GA1', 'GA2', 'GA3', 'GA4', 'GA5', 'GA6', 'GA7', 'GA8', 'GA9', 'GA10', 'GA11', 'GA12', 'M-fb', 'M-pnlf', 'G3'): extra.append("-igfxdbeo")
    elif exp in ('selftest', 'alive'):
        keep_vesa, with_plat, static = True, False, True
        extra = ["-igfxtgl", "-igfxtgl" + exp]
    elif exp.startswith(('stop=', 'fn=', 'fnret=')):
        k, n = exp.split('=', 1); int(n)
        static = True
        extra = ["-igfxtgl", {"stop": "igfxtglstop", "fn": "igfxtglfn", "fnret": "igfxtglfnret"}[k] + "=" + n]
    else:
        sys.exit("unknown experiment %r" % exp)

    if exp != 'revert':
        a = base_args if keep_vesa else base_args.replace('-igfxvesa', '')
        if exp in ('GA1', 'GA2', 'GA3', 'GA4', 'GA5', 'GA6', 'GA7', 'GA8', 'GA9', 'GA10', 'GA11', 'GA12'): extra += ['-allow3d', '-disablegfxfirmware']
        if exp in ('GA2', 'GA3', 'GA4', 'GA6', 'GA7', 'GA8', 'GA9', 'GA10', 'GA11', 'GA12'): extra += ['igfxtglss=6']
        if exp == 'GA5': extra += ['igfxtglss=4']
        if exp in ('GA3', 'GA4', 'GA5', 'GA6', 'GA7', 'GA8', 'GA9', 'GA10', 'GA11', 'GA12'): extra += ['igfxtglcsb=1']
        if exp in ('GA6', 'GA7', 'GA8', 'GA9', 'GA10', 'GA11', 'GA12'): extra += ['igfxtglhang=1']
        if exp in ('GA7', 'GA8', 'GA9', 'GA10', 'GA11', 'GA12'): extra += ['igfxtglxl=1']
        if exp == 'GA12': extra += ['igfxtglres=3']
        nv['boot-args'] = ' '.join(a.split() + extra)
        props = {'device-id': le32(dev)}
        if with_plat: props['AAPL,ig-platform-id'] = le32(plat)
        p['DeviceProperties']['Add'][IGPU] = props
        if exp not in ('GA1', 'GA2', 'GA3', 'GA4', 'GA5', 'GA6', 'GA7', 'GA8', 'GA9', 'GA10', 'GA11', 'GA12'):
            p['Kernel'].setdefault('Block', []).append(block_accel())
        if static:
            p['Kernel'].setdefault('Patch', []).append(static_dvmt_patch(dvmt_mb))
        if exp in ('M', 'N', 'P', 'P2', 'Q', 'R', 'S', 'GA1', 'GA2', 'GA3', 'GA4', 'GA5', 'GA6', 'GA7', 'GA8', 'GA9', 'GA10', 'GA11', 'GA12', 'M-pnlf'):
            hit = [a for a in p['ACPI']['Add'] if a.get('Path') == 'SSDT-PNLF.aml']
            if not hit: sys.exit("SSDT-PNLF.aml is not listed in ACPI/Add of the base config")
            hit[0]['Enabled'] = True

    if exp in ('N', 'P', 'P2', 'Q', 'R', 'S', 'GA1', 'GA2', 'GA3', 'GA4', 'GA5', 'GA6', 'GA7', 'GA8', 'GA9', 'GA10', 'GA11', 'GA12'):
        if not any(k['BundlePath'] == 'BrightnessKeys.kext' for k in p['Kernel']['Add']):
            p['Kernel']['Add'].append({'Arch': 'x86_64', 'BundlePath': 'BrightnessKeys.kext', 'Comment': 'ACPI brightness key notifications (Notify LCD 0x86/0x87)',
                'Enabled': True, 'ExecutablePath': 'Contents/MacOS/BrightnessKeys', 'MaxKernel': '', 'MinKernel': '', 'PlistPath': 'Contents/Info.plist'})

    if exp in ('P', 'P2', 'Q', 'R', 'S', 'GA1', 'GA2', 'GA3', 'GA4', 'GA5', 'GA6', 'GA7', 'GA8', 'GA9', 'GA10', 'GA11', 'GA12'):
        if not any(a.get('Path') == 'SSDT-DOSI.aml' for a in p['ACPI']['Add']):
            p['ACPI']['Add'].append({'Comment': 'Dell OS identity for macOS: lets the firmware forward brightness keys', 'Enabled': True, 'Path': 'SSDT-DOSI.aml'})

    with open(dst, 'wb') as f:
        plistlib.dump(p, f, sort_keys=False)
    print("wrote       :", dst)
    print("boot-args   :", nv['boot-args'])
    dp = p['DeviceProperties']['Add'].get(IGPU)
    print("IGPU        :", ' '.join('%s=%s' % (k, v.hex()) for k, v in dp.items()) if dp else "no DeviceProperties injected (stock)")
    print("Kernel/Block:", [(b['Identifier'], b['Strategy']) for b in p['Kernel'].get('Block', [])] or 'none')
    print("Kernel/Patch:", [k['Comment'] for k in p['Kernel'].get('Patch', [])] or 'none')
    print("ACPI/Add    :", [a['Path'] for a in p['ACPI']['Add'] if a.get('Enabled')])
    print("Kexts       :", [k['BundlePath'] for k in p['Kernel']['Add'] if k.get('Enabled')][-4:])

if __name__ == '__main__':
    main()
