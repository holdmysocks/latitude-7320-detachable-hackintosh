# Symbol inventory: Tahoe `AppleIntelICLLPGraphicsFramebuffer`

Written on [MBP], 2026-09-26, for HANDOFF-3 Task B. The content is static
analysis only. Nothing here was booted.

Conventions: **Fact** means read directly from the binary or a source file.
**Inference** means my interpretation, which a boot has not confirmed.

## Source binary

- `kext-capture/AppleIntelICLLPGraphicsFramebuffer.kext` holds only
  `Info.plist`, `version.plist` and `_CodeSignature`, with **no executable**.
  The binary came from `kext-capture/SystemKernelExtensions.kc`, fileset entry
  `com.apple.driver.AppleIntelICLLPGraphicsFramebuffer` (vmaddr `0x13fd9000`,
  file offset 335384576).
- Captured OS: macOS 26.6 (25G72), per `kext-capture/macos-version.txt`.
- Extraction: blacktop `ipsw` was not installed, and I didn't install it. I
  used a small local Python script instead. It copies the entry's segments and
  its own `LC_SYMTAB` (3835 symbols) into a standalone x86_64 `MH_KEXT_BUNDLE`
  that `nm`, `otool` and `llvm-objdump` can read. Chained fixups are not
  rebuilt, so the output is good for inspection only, never for loading.
  Direct `call rel32` targets resolve correctly. Pointers in `__DATA` are raw
  kernel-cache chained pointers, so the low 30 bits give the target.
- Full symbol list, demangled: `icllp-symbols.txt` (`nm -m | c++filt`).
  **Note:** the Tahoe framebuffer's symbols are all `non-external (was a private
  external)`. That is normal for KC kexts, and Lilu's `solveSymbol` reads the
  symtab, so this does not block WG.

---

## Q1. Do WG's hook targets exist?  **Yes, both.**

```
000000001400c46e (__TEXT,__text) non-external (was a private external) __ZN31AppleIntelFramebufferController14ReadRegister32Em
000000001400c5b6 (__TEXT,__text) non-external (was a private external) __ZN31AppleIntelFramebufferController15WriteRegister32Emj
```

These are the exact strings WG uses for SKL, KBL, CFL and ICL in
`MMIORegistersReadSupport` / `MMIORegistersWriteSupport::processFramebufferKext`
(checked in `kern_igfx.cpp` at `0762cec`). **Inference:** Step 2 should log
`RRS/RWS: Will setup ... SKL/KBL/CFL/ICL`, and there should be no `Failed to
resolve`.

**Fact: these two functions are leaf accessors,** not dispatchers. Each does
its own bounds check (`offset < [this+0xc38] - 4`) and then touches MMIO at
`[this+0x9b8] + offset` itself. `WriteRegister32(unsigned long, unsigned int)`
also calls `captureMMIO()` and caches writes to `0x6F800`. Nothing else routes
through them except these thin forwarders, which the tracer does see:

| Forwarder | Goes to |
|---|---|
| `AppleIntelPort::readRegister32(unsigned int)` | tail-jump to `ReadRegister32(unsigned long)` via `_gController` |
| `AppleIntelPort::writeRegister32(unsigned int, unsigned int)` | `WriteRegister32(unsigned long, unsigned int)` |
| `AppleIntelFramebuffer::DisplayReadRegister32(unsigned int*, unsigned long)` / `DisplayWriteRegister32(unsigned long, unsigned int)` | the hooked pair, under a lock |

**Fact: sibling accessors the tracer does NOT see.** Each one does its own MMIO
and doesn't call the hooked pair:

```
AppleIntelFramebufferController::ReadRegister32(void volatile*, unsigned long)
AppleIntelFramebufferController::WriteRegister32(void volatile*, unsigned long, unsigned int)
AppleIntelFramebufferController::FastReadRegister32(void volatile*, unsigned long)
AppleIntelFramebufferController::FastWriteRegister32(void volatile*, unsigned long, unsigned int)
AppleIntelFramebufferController::SafeReadRegister32(unsigned long)            (+ void volatile* overload)
AppleIntelFramebufferController::SafeWriteRegister32(unsigned long, unsigned int) (+ void volatile* overload)
AppleIntelFramebufferController::ReadRegister16 / ReadRegister64 / WriteRegister64 (both overloads)
__SafeWriteRegister32
SafeForceWake(bool, unsigned int)   (uses its own global base copy, RC6_RegBase)
AppleIntelMEIDriver::readHostCsr / writeHostCsr / readMECsr ...   (HECI, a different PCI device)
```

## Q2. Does Apple load DMC/CSR firmware?  **Yes. ICL DMC firmware is embedded, and `start()` uploads it.**

Symbols matching `DMC|CSR|Firmware|loadFW`:
```
0000000014092bb0 (__DATA,__data) _CSR_PATCH_AX
0000000014095e00 (__DATA,__data) _CSR_PATCH_B0plus
AppleIntelMEClientController::getFirmwareMode()        (ME, unrelated)
AppleIntelMEIDriver::readHostCsr / writeHostCsr / ...  (HECI "CSR", unrelated)
```
There's no `DMC*` symbol and no load-from-file routine. The payload is compiled
in.

**Fact.** `AppleIntelFramebufferController::hwInitializeCState()`
(`0x140110a6`) does the following:

1. Returns immediately unless `[this+0xb38] == 1`.
2. Picks a blob using `[this+0xc9c]`. When it is 0, it picks `_CSR_PATCH_AX`,
   length `0x3244` bytes (3217 dwords). Otherwise it picks `_CSR_PATCH_B0plus`,
   length `0x322c` bytes (3211 dwords).
3. Writes the blob dword-by-dword to MMIO `0x80000 + 4*i` with
   **`FastWriteRegister32(void volatile*, ...)`, which is unhooked and
   invisible to the tracer**.
4. Then makes four **hooked** writes:

   | Offset | Value | i915 name (checked in Linux master headers) |
   |---|---|---|
   | `0x8F074` | `0x00006FC0` | `DMC_SSP_BASE` (`intel_dmc_regs.h`) |
   | `0x8F004` | `0x00A40088` | `DMC_HTP_SKL` (`intel_dmc_regs.h`) |
   | `0x8F034` | `0xC003B400` | `DMC_LAST_WRITE` (`intel_dmc_regs.h`) |
   | `0x45520` | `0x00000002` | `DC_STATE_DEBUG`, bit 1 = `DC_STATE_DEBUG_MASK_MEMORY_UP` (`intel_display_regs.h`) |

5. Tail-calls `hwConfigureCustomAUX(true)`, which makes 14 hooked writes.

`0x80000` is `DMC_MMIO_START_RANGE` / the base of `DMC_PROGRAM` in
`intel_dmc_regs.h`. Both blobs start with dword `0x0B004040`. The second dword
is `0x41` for AX and `0x10008` for B0+.

**The gate is a boot-arg (Fact).** `getOSInformation()` sets `[this+0xb38] = 1`
by default. It then calls what is presumably `PE_parse_boot_argn`
(**inference**, from the 4-byte size argument) on the string **`dc6config`**:
- `dc6config=0` sets `0xb38 = 0`, so `hwInitializeCState` skips the whole DMC
  upload.
- `dc6config=1`, any other non-zero value, or no boot-arg keeps it at 1.
- `dc6config=5` also sets `[this+0xb40] = 1`.

`0xb38` is also read by `enableHWDC6`, `disableHWDC6`, `isHWDC6Enabled`,
`AppleIntelPowerWell::probePowerWellsState`, `setupOptimizedDBUF`,
`hwConfigureCustomAUX` and several `BanksiaTcon` (PSR) paths. So
`dc6config=0` turns off more than the upload.

**Inference.** Tiger Lake would get Ice Lake DMC firmware (i915 uses a separate
`tgl_dmc` blob for display ver 12). Which blob gets chosen depends on how the
ICL driver sets `0xc9c` on TGL, and I have not traced that. This is the §5
"High if it does" suspect, and it **does**.

**What this means for the bisection (inference).** The ~3.2k program writes
don't increment the tracer's counter. If the DMC upload itself, or the firmware
starting once `DMC_SSP_BASE`/`DMC_HTP` are written, is the killer, bisection
will converge with the last surviving access being whatever precedes
`hwInitializeCState` in `start()`, and access N+1 will be `W 0x8F074 =
0x6FC0`. A convergence on `0x8F074`, `0x8F004`, `0x8F034` or `0x45520` should
be read as "DMC", not as that single register. It is also possible that a
running DMC resets the platform a little later, asynchronously. In that case
the boundary could look non-monotonic or land on an innocuous access.

A cheap cross-check that is independent of the tracer is one boot with
`dc6config=0` added to an otherwise-unchanged reset config. That is one
variable. This is only a suggestion. It is not in START-HERE and I have not
added it to the harness.

## Q3. Type-C, PHY, power-well, AUX and FIA functions

These are whole functions, the cheap targets for neutralising later. **Fact:**
every one of them does its MMIO through the hooked pair, with **zero**
unhooked-accessor calls and zero direct uses of the MMIO base. Numbers are
static call sites (hooked R / hooked W).

| Function | hR | hW |
|---|---:|---:|
| `AppleIntelPowerWell::init(AppleIntelFramebufferController*)` | – | – |
| `AppleIntelPowerWell::probePowerWellsState()` | 3 | 0 |
| `AppleIntelPowerWell::enableDisplayEngine()` / `disableDisplayEngine()` | 10 / 4 | 8 / 3 |
| `AppleIntelPowerWell::hwSetPowerWellStatePG(bool, unsigned int)` | 13 | 18 |
| `AppleIntelPowerWell::hwSetPowerWellStateDDI(bool, unsigned int)` | 1 | 2 |
| `AppleIntelPowerWell::hwSetPowerWellStateAux(bool, unsigned int)` | 11 | 11 |
| `AppleIntelPowerWell::{enable,disable}PowerWell{PG,DDI,Aux}(unsigned int)`, `overridePowerWellsState(bool)`, `restorePowerWellsState()` | wrappers | |
| `AppleIntelPort::{enable,disable}PowerWell{Aux,DDI}()` | wrappers | |
| `AppleIntelPortHAL::enableMgPhyClocks()` / `disableMgPhyClocks()` | 10 / 4 | 15 / 3 |
| `AppleIntelPortHAL::setMgDPMode()` | 2 | 2 |
| `AppleIntelPortHAL::getMgPhyLaneConfigBitMask()`, `getConfiguredMgPhyLaneConfig()` | 1, 1 | 0 |
| `AppleIntelPortHAL::setFIALaneCount(unsigned int)` / `getFIALaneCount()` | 1 | 1 |
| `AppleIntelPortHAL::enableComboPhy()` | 5 | 6 |
| `AppleIntelPortHAL::setPhyClockGating(bool)` | 3 | 3 |
| `AppleIntelPortHAL::setPortMode(AppleIntelPort::PortMode)`, `probePortMode()` | 4, 1 | 3, 0 |
| `AppleIntelPortHAL::runAUXCommand(AppleIntelPort::AUX_Command, unsigned int*, unsigned int, bool)` | 9 | 7 |
| `AppleIntelPortHAL::setVoltageSwingAndPreEmphasis(...)` | 26 | 26 |
| `AppleIntelFramebufferController::hwConfigureCustomAUX(bool)` | 0 | 14 |
| `AppleIntelFramebufferController::isTypeCInterruptPending(unsigned int)` | – | – |
| `AppleIntelFramebufferController::enableVDDForAux(AppleIntelPort*)` / `disableVDDForAux(AppleIntelPort*)` | – | – |

Not present (Fact): no `TypeC*` class or functions other than
`isTypeCInterruptPending`, no `Dekel`/`DKL`, no `TCCold`/`TC_cold`, and no
`PowerGate` symbol. The Type-C PHY code is **MG PHY only** (`*MgPhy*`,
`setMgDPMode`), which is ICL's PHY. **Inference:** on TGL, the MG PHY register
writes land where TGL has the Dekel PHY, and nothing blocks TC-cold first.
That matches the §5 "High" suspect. The full list is in `icllp-symbols.txt`.
Grep it for `PowerWell|PortHAL|Mg|FIA|AUX`.

## Q4. CDCLK: **all three exist on Tahoe**

```
00000000140374aa AppleIntelFramebufferController::probeCDClockFrequency()          hR 2  hW 0
0000000014036e00 AppleIntelFramebufferController::setCDClockFrequency(unsigned long long)  hR 2  hW 3
00000000140373c6 AppleIntelFramebufferController::disableCDClock()                 hR 2  hW 1
```
Also present: `initCDClock()` (called from `start()`), `calculateCDClockFrequency(unsigned long long)`,
`calculateCDClockVoltageLevel()`, `setCDClockFrequencyOnHotplug()`, and a
`setCDClockFrequency` `.cold.1` fragment at `0x140569de`.

## Q5. How blind is the tracer?

Method: I disassembled the whole binary with `llvm-objdump`. For each
function I counted static call and tail-jump sites to the hooked pair (and its
forwarders), to the unhooked siblings, and to instructions reading the MMIO
base field `[this+0x9b8]` outside the accessors. Then I walked **direct** call
edges from `AppleIntelFramebufferController::start(IOService*)`. Its indirect
calls go to slots whose targets in the controller's vtable are IOService/kernel
methods, and many go to other objects, so they were not followed. The tool is
static, so loops count once.

| Scope | hooked R | hooked W | unhooked accessor sites | `0x9b8` base uses |
|---|---:|---:|---:|---:|
| `start()` itself | 4 | 4 | 0 | 3 (map setup, copy to `RC6_RegBase`, pass to `registerWithAICPM`), no direct access |
| `start()` + direct callees, depth ≤ 8 (218 functions, 68 touch MMIO) | 250 | 197 | 7 (`FastWriteRegister32` ×1 in `hwInitializeCState`; `SafeWriteRegister32` ×3; `WriteRegister64` ×3 for GTT/cursor) | 4 |
| Whole binary | 790 | 815 | 72 | 64 |

Whole-binary unhooked use is concentrated in the interrupt path
(`processDEInterrupt` 17R+17W Fast, `ProcessInterrupt` 3) and debug dumping
(`DumpDisplayControllerInfo` 20R Fast). The rest is `SafeWriteRegister32` in
`InterruptThreshold::updateHW` / `write_gstate`, `WriteRegister64` for GTT
entries, and `SafeForceWake` through `RC6_RegBase`. I found no inlined
`mov [base+imm]` MMIO in the `start()` hardware-init path.

**Rough ratio.**
- **Statically:** about 98% of `start()`-path MMIO sites are visible (447
  hooked vs 7 unhooked).
- **Dynamically:** the single `FastWriteRegister32` loop in
  `hwInitializeCState` performs about 3.2k invisible writes (the DMC program).
  That is probably more than all the hooked accesses before it put together.
  This is an inference; I haven't measured it.

**Inference, bottom line.**
- A clean bisection is plausible for everything except the DMC upload. Power
  wells, MG PHY, FIA, AUX and CDCLK are fully visible.
- If the boundary lands immediately before `W 0x8F074`, treat it as "DMC
  upload or DMC start", not as that register. Test it with `dc6config=0`
  rather than bisecting further.
- The interrupt handler is blind. Its accesses come after
  `hwEnableInterrupts()`, near the end of `start()`. If the kill happens after
  interrupts are enabled, expect a non-monotonic or "innocuous boundary"
  result. That is the HANDOFF-2 §7 stop condition.

### Order of hardware-relevant direct calls in `start()` (Fact, from disassembly)

`initInterruptService` → (hooked W) → `getOSInformation` (parses `dc6config`)
→ hooked R/W → `registerWithAICPM` → `FBMemMgr_Init` → `initCDClock` →
`readEDIDOverrideProperties` → hooked R → `AppleIntelScaler::init` /
`AppleIntelPlane::init` → `AppleIntelPort::allocatePorts` →
**`AppleIntelPowerWell::init`** → `AppleIntelDisplayPath::init` →
`AppleIntelFramebuffer::init` → `initPlatformWorkarounds` →
`setupBootDisplay` → `hwSetPanelPowerConfig` → `hwInitializeLatencyValues` →
**`hwInitializeCState` (DMC upload)** → hooked R/W → `hwSetupCursorMemory` →
`setupWorkLoop` → `initPMRegisters` → `hwGetMemoryLayoutEFI` →
`AppleIntelPAVP::init` → `createMEIDriver` →
`createAppleGraphicsDeviceControlnub` → `addPMNotification` →
**`hwEnableInterrupts`** → `createMEClientController` → hooked R/W.

## Source-level check of the §A.2 "identical without `-igfxtgl`" contract

This was checked while doing B. Nothing here was built or booted.
- **Fact:** without `-igfxtgl`, `IGFX::init()` leaves `currentFramebuffer`
  null on Tiger Lake, as upstream does, and `TigerLakeTracer::processKernel`
  leaves `enabled = false`.
- **Fact:** RRS and RWS switch themselves on only for submodules with
  `enabled == true`.
- **Fact:** the tracer's unconditional `requiresPatchingFramebuffer = true` in
  `init()` matches what upstream submodules (`ForceCompleteModeset`,
  `AGDCDisabler`, `TypeCCheckDisabler`, and others) already do, so it changes
  nothing.
