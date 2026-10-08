# WhateverGreen patches for Tiger Lake on the Ice Lake framebuffer

Three patches against [acidanthera/WhateverGreen](https://github.com/acidanthera/WhateverGreen) commit
`0762cecc2a70054cd4dc3cf4d08979aca6acd9bb` (1.7.1), applied in order. Only 0003 is needed for a working display;
0001 and 0002 are the diagnostics it was developed on top of, and 0003 does not apply without them.

No kext binary is committed. Build it yourself (below).

| Patch | What it adds | Needed to boot? |
|---|---|---|
| `0001-tigerlake-icllp-mmio-tracer.patch` | `-igfxtgl`: route the ICL LP framebuffer on a CPU detected as Tiger Lake and count register accesses; `igfxtglstop=N` panics before access N | no |
| `0002-tgl-function-tracer.patch` | `-igfxtglselftest`, `igfxtglfn=`, `igfxtglfnret=`: hook self-test and function-level tracing | no |
| `0003-tgl-register-map.patch` | `igfxtglmap=<mask>`: translate the Ice Lake display registers Tiger Lake moved | **yes** |

Use 0003 together with `lilucpu=12`, so that WhateverGreen takes its Ice Lake path and every stock Ice Lake fix
(`-igfxdvmt`, `-igfxcdc`, connector patching) stays available. 0003 looks at the real CPU model (`0x8C`/`0x8D`), not
at the overridden generation, and does nothing on any other CPU. Without `igfxtglmap` the build behaves like
upstream.

Why each translation exists: [`../research/LAYER3.md`](../research/LAYER3.md).

## `igfxtglmap` bits

| Bit | Feature |
|---|---|
| `0x0001` | map the eDP transcoder block (`0x6Fxxx`, `0x7Fxxx`) onto transcoder A |
| `0x0002` | DP_TP_CTL / DP_TP_STATUS / DDI_DP_COMP of DDI A: per port (`0x64040`) → per transcoder (`0x60540`) |
| `0x0004` | TRANS_DDI_FUNC_CTL DDI select encoding, both directions |
| `0x0008` | TRANS_CLK_SEL encoding, both directions |
| `0x0010` | combo DPLL CFGCR0/1 addresses (`0x164000…` → `0x164284…`); DCO fraction halved at a 38.4 MHz reference |
| `0x0020` | set TRANS_CLK_SEL_A and the DDI select before DP_TP_CTL is enabled; turn the driver's write of 0 to TRANS_CLK_SEL_A into "DDI A" while the port is active. Nothing is released after the port is disabled: doing so froze the machine at display sleep |
| `0x0040` | publish a state record to the IORegistry (**from inside the hook**) |
| `0x0080` | publish the state record to NVRAM (**resets this machine; do not use**) |
| `0x0100` | `IOLog` translated accesses (not visible in the unified log on Tahoe) |
| `0x0400` | with `0x0001`: map eDP reads only after the driver's first write to that block |
| `0x0800` | with `0x0001`: map only the stream registers (`0x6F000–0FF`, `0x6F400–41F`, `0x7F000–0FF`), not PSR/VRR/DIP |
| `0x2000` | diagnostic snapshot of 48 registers to `/Users/Shared/tgl-map-state.bin` (firmware state at the first access; again 75 s and 180 s after the first DP_TP_CTL enable). Decode with `tools/mac/decode-tglmap.py` |
| `0x4000` | backlight: keep the firmware's PWM frequency and duty (drops the driver's writes) |
| `0x8000` | backlight with brightness control: keep the firmware's PWM frequency, rescale duty from the driver's period and the level range given by `igfxtglblmax`; a zero duty is passed through and the level restored when the PWM is enabled again. Use this **or** `0x4000`, and not together with `-igfxblr` |
| `0x10000` | **diagnostic.** Register trace on disk (`/Users/Shared/tgl-trace.bin`, decode with `tools/mac/decode-tgltrace.py`). Armed by a zero backlight duty (brightness slider to minimum) or at `igfxtgltraceat=<uptime s>`; runs for 120 s; holds the driver until each write access is on disk. The file is never closed, so a clean shutdown hangs afterwards: power off by hand |
| `0x40000` | with `0x10000`: do not hold the driver; it runs at normal speed and the last millisecond or two may be lost |

`igfxtglblmax=<level>` is the highest backlight level AppleBacklight sends for the `SSDT-PNLF` `_UID` in use
(default `0xFFFF`; `_UID` 15 needs `0xAD9`).

`-igfxtglmap` alone means `0x3F`. The working configuration is **`igfxtglmap=0xA83F igfxtglblmax=0xAD9`**
(`0x01 0x02 0x04 0x08 0x10 0x20 0x800 0x2000 0x8000`), together with the driver's own `dc6config=0`. The `0x2000` snapshot never fires in that configuration
(the boot is seamless, so DP_TP_CTL is not re-enabled) and can be dropped: `0x883F`.

`-igfxtglfwpll` additionally drops the driver's DPLL config writes and keeps whatever the firmware programmed.

## Building

With Xcode:

```bash
git clone https://github.com/acidanthera/WhateverGreen && cd WhateverGreen
git checkout 0762cecc2a70054cd4dc3cf4d08979aca6acd9bb
for p in 0001 0002 0003; do git apply ../WhateverGreen-patches/$p-*.patch; done
git clone --depth 1 https://github.com/acidanthera/MacKernelSDK
# Lilu 1.7.2 DEBUG release, unpacked so that ./Lilu.kext exists (it carries the headers and plugin_start.cpp)
xcodebuild -configuration Release
```

Without Xcode, with Command Line Tools only (this is how the builds in the run log were made):

```bash
# in the patched tree, after MacKernelSDK and Lilu.kext are in place:
clang++ -fno-objc-arc -framework Foundation -framework Cocoa -o ResourceConverter.bin ResourceConverter/main.mm
./ResourceConverter.bin Resources WhateverGreen/kern_resources.cpp WhateverGreen/kern_resources.hpp
../WhateverGreen-patches/build-weg-clt.sh . out
```

`build-weg-clt.sh` mirrors the project's Release settings. Building 0001+0002 with it gives a kext whose imported
symbols are identical to the Xcode build of the same source.

## Two rules learned the hard way

- **Never write NVRAM from this kext.** On this machine it resets the platform, from any context.
- **Do not call blocking kernel services from inside the register hooks.** Read registers there if you must;
  publish from a thread call, to a file.
- **Do not tidy up the hardware after the driver.** The one piece of this patch that wrote registers the driver had
  not asked for (releasing the transcoder after port disable) froze the machine at display sleep.
- **`vnode_close` from a thread call panics** (`zone_require_ro failed`): there is no process context.
