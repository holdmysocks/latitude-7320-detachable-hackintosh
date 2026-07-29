# 04 — Installation

Two ways to get an installer. Then the five things that actually blocked the
install here — none of which produce a useful error message.

---

## 7. Getting an installer onto USB

### Option A — `macrecovery` (no Mac required)

`macrecovery` ships with OpenCore. It is pure Python, stdlib only, and runs on
macOS, Windows or Linux. It downloads a ~700 MB recovery image that then
downloads the OS during install, so **you need wired internet at install time**
— a USB-C Ethernet adapter. Wi-Fi does not exist until `itlwm` is enabled
after install.

```bash
python3 macrecovery.py -b Mac-CFF7D910A743CAAF -m 00000000000000000 -os latest download
```

The board ID above is what OpenCore's own `recovery_urls.txt` documents for
Tahoe. It is **only** used to ask Apple which image to serve — it does not need
to match your `MacBookPro16,2` SMBIOS.

Result is a `com.apple.recovery.boot` folder containing `BaseSystem.dmg` and
`BaseSystem.chunklist`. Copy the whole folder to the **root** of the same USB
stick that holds `EFI\`:

```
Y:\EFI\BOOT\BOOTx64.efi
Y:\EFI\OC\config.plist
Y:\com.apple.recovery.boot\BaseSystem.dmg
Y:\com.apple.recovery.boot\BaseSystem.chunklist
```

One stick. No `createinstallmedia`, no second drive.

> Chunklists are ~3.6 KB, not "a few hundred KB". 3604 bytes is correct.

### Option B — `createinstallmedia` from a Mac

Buildable from an Apple Silicon Mac — `createinstallmedia` produces a valid
Intel installer from Apple Silicon, since `InstallAssistant` carries both
architectures.

Use a **USB 2.0** stick if available. Format **Mac OS Extended (Journaled)** /
**GUID Partition Map**, named `MyVolume`.

```bash
sudo /Applications/Install\ macOS\ Tahoe.app/Contents/Resources/createinstallmedia \
  --volume /Volumes/MyVolume
```

Then mount its EFI partition and copy the `EFI` folder to the root.

---

## 8. The five things that actually bit us

### 8.1 Recovery entry invisible in the picker

`Misc > Boot > HideAuxiliary = True` hides **macOS recovery entries** along with
Reset NVRAM. Press **Space** to reveal, or set it to `False`. Symptom is a
picker showing only Windows.

*The config in this repo ships `HideAuxiliary = False` for exactly this reason.*

### 8.2 Recovery entry still invisible after Space

`Misc > Security > DmgLoading = Signed` makes OpenCore verify the recovery image
and **drop the entry silently** on failure — no error, no log line at default
verbosity. Set to `Any` to install, then put it back to `Signed` afterwards.

Also set `Misc > Debug > Target = 67` to get a log file on the ESP. `Target = 3`
logs to screen only, which removes the diagnostic exactly when it's needed.

*The config in this repo ships `DmgLoading = Any` and `Target = 67` — install
values. Revert both after install:
[05 — post-install §9.4](05-post-install.md#94-two-config-changes-internal-copy-only).*

### 8.3 The entry is named after the volume, not the OS

It appears as **`OCBOOT (external) (dmg)`** — OpenCore falls back to the FAT32
volume label when it can't read a name from inside the DMG. That is the
recovery image. Boot it.

Healthy progress markers in the verbose text:

```
#[EB.B.SBS|SZ] 723512                      boot.efi sized the BaseSystem
#[EB|B:SHA] <c1f046...>                    image hash accepted
#[EB.LD.LKC|R.1] BootKernelExtensions.kc   loading the kernel collection
```

`Err(0xE)` on `PWLFNV` / `PWLFRTC` is `EFI_NOT_FOUND` — `boot.efi` checking for
a hibernation image that doesn't exist on a cold boot. Every Mac logs these.

> `[EB|LOG:EXITBS:START]` as the last line **of the file log** is normal, not a
> hang — OpenCore cannot write to FAT after ExitBootServices. It only indicates
> a hang when frozen **on screen**.

### 8.4 ⚠️ Disk Utility can't use mid-disk free space

This is the big one. `diskutil list` showed:

```
disk3s1   EFI                     209.7 MB
disk3s2   Microsoft Reserved       16.8 MB
disk3s3   Microsoft Basic Data    129.1 GB   <- Windows C:
          (free space)            125.8 GB   <- identifier column is "-"
disk3s4   Windows Recovery        891.3 MB
```

Windows places WinRE *after* `C:`, so shrinking `C:` leaves the gap **in the
middle of the disk**. Free space with identifier `-` cannot be addressed, so
Disk Utility greys out `+` and explains nothing.

> **Do NOT run `diskutil addPartition disk3s3 ...`.** Given a partition
> identifier rather than a free-space identifier, that command *shrinks the
> named partition*. `disk3s3` is Windows, and macOS cannot safely resize NTFS.

**Fix: create the partition from Windows first.**

1. Boot Windows → `diskmgmt.msc`
2. Right-click the unallocated block → **New Simple Volume**, full size, NTFS,
   label `TAHOE`, **do not assign a drive letter**
3. Back in recovery: Disk Utility → Show All Devices → select the **`TAHOE`
   partition** (not the disk) → **Erase** → APFS

Erase on a single partition only rewrites that partition and flips its GPT type
GUID to `Apple_APFS`. `C:` and WinRE are untouched. Confirm the size reads
~125.8 GB and that it sits under `disk3 (internal, physical)` before clicking.

### 8.5 Setup Assistant hangs on "Update Mac Automatically"

Round-trips to Apple's software-update servers and spins forever rather than
timing out. **Unplug Ethernet**, wait a few minutes; if still stuck, force power
off and boot back into Tahoe. Setup Assistant resumes and skips
server-dependent steps with no network. Nothing is lost — the OS install
completed before this screen.

Then immediately: **System Settings → General → Software Update → ⓘ → disable
everything**, especially "Install macOS updates." An unattended update can rev
past kext support and re-seal the system volume.

---

Next: [05 — post-install](05-post-install.md)
