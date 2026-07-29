# Drivers

All four come from the official OpenCore **1.0.7 RELEASE** archive
(<https://github.com/acidanthera/OpenCorePkg/releases>). None are committed
here — [`tools/fetch-components.ps1`](../../../tools/fetch-components.ps1)
copies them out of the release zip into this folder.

| Driver | Enabled | Why |
|---|---|---|
| `OpenRuntime.efi` | ✅ | **required.** NVRAM and memory-map services OpenCore cannot work without |
| `OpenHfsPlus.efi` | ✅ | HFS+ driver — needed to read a `createinstallmedia` installer volume |
| `ResetNvramEntry.efi` | ✅ | adds a Reset NVRAM entry to the picker |
| `OpenCanopy.efi` | ⚪ | graphical picker. Config uses `PickerMode = Builtin`, so it is loaded but unused |

`AudioDxe.efi` is **not** enabled. There is no HD Audio controller on this
machine to drive — the codecs are SoundWire — so boot chime is impossible.
See [`../../../docs/00-hardware-survey.md`](../../../docs/00-hardware-survey.md#14-audio--permanently-silent).

`EFI/OC/Tools/OpenShell.efi` comes from the same archive; it is enabled as an
auxiliary picker entry, which is useful when a graphics experiment leaves the
machine in a state where you need to inspect the ESP from firmware.

## Version pinning

`ocvalidate` is version-locked: the 1.0.7 binary refuses to reason about a
config from a different generation. If you upgrade OpenCore, upgrade
`OpenCore.efi`, `BOOTx64.efi`, every `.efi` in this folder and `ocvalidate`
together, from the same release archive. Mixing versions is the single most
common way to produce a boot failure with no diagnostic.
