#!/usr/bin/env bash
# fetch-components.sh - download OpenCore and the kexts into EFI/
#
#   ./fetch-components.sh              # newest release of each project
#   ./fetch-components.sh --tested     # the exact versions this build was tested on
#
# macOS / Linux equivalent of fetch-components.ps1. Needs curl, unzip, python3.
#
# Nothing third-party is committed to this repository, so this script is how
# EFI/ becomes bootable.

set -euo pipefail

TESTED=0
[[ "${1:-}" == "--tested" ]] && TESTED=1

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$here")"
efi="$root/EFI"
dl="$here/_downloads"
work="$dl/_extract"

mkdir -p "$dl" "$work" "$efi/OC/Kexts" "$efi/OC/Drivers" "$efi/OC/Tools" "$efi/BOOT"

# repo | tested version | asset regex | kexts (space separated, or OPENCORE)
components=(
  "acidanthera/OpenCorePkg|1.0.7|^OpenCore-.*-RELEASE[.]zip$|OPENCORE"
  "acidanthera/Lilu|1.7.2|RELEASE[.]zip$|Lilu.kext"
  "acidanthera/VirtualSMC|1.3.7|RELEASE[.]zip$|VirtualSMC.kext SMCProcessor.kext SMCBatteryManager.kext SMCDellSensors.kext"
  "acidanthera/WhateverGreen|1.7.0|RELEASE[.]zip$|WhateverGreen.kext"
  "acidanthera/NVMeFix|1.1.3|RELEASE[.]zip$|NVMeFix.kext"
  "acidanthera/BrightnessKeys|1.0.3|RELEASE[.]zip$|BrightnessKeys.kext"
  "acidanthera/BrcmPatchRAM|2.7.2|RELEASE[.]zip$|BlueToolFixup.kext"
  "acidanthera/VoodooPS2|2.3.7|RELEASE[.]zip$|VoodooPS2Controller.kext"
  "1Revenger1/ECEnabler|1.0.6|RELEASE[.]zip$|ECEnabler.kext"
  "USBToolBox/kext|1.2.0|[.]zip$|USBToolBox.kext"
  "OpenIntelWireless/itlwm|2.3.0|itlwm.*[.]zip$|itlwm.kext"
  "lshbluesky/IntelBluetoothFirmware|2.5.1|[.]zip$|IntelBluetoothFirmware.kext IntelBTPatcher.kext"
)

# Must stay absent - see EFI/OC/Kexts/KEXTS.md
excluded=("IntelBluetoothInjector.kext" "AirportItlwm.kext")

pick_asset() {  # <json> <regex> -> download url + name
  python3 - "$2" <<'PY'
import json,re,sys
rx=re.compile(sys.argv[1])
rel=json.load(sys.stdin)
assets=rel.get("assets",[])
m=[a for a in assets if rx.search(a["name"])] or [a for a in assets if a["name"].endswith(".zip")]
if not m:
    sys.exit("no usable asset: " + ", ".join(a["name"] for a in assets))
print(rel["tag_name"]); print(m[0]["name"]); print(m[0]["browser_download_url"])
PY
}

printf '%-42s %-12s %-12s\n' "COMPONENT" "FETCHED" "TESTED" > "$dl/summary.txt"

for entry in "${components[@]}"; do
  IFS='|' read -r repo tested rx kexts <<< "$entry"
  echo ""
  echo "=== $repo ==="

  if [[ $TESTED -eq 1 ]]; then url="https://api.github.com/repos/$repo/releases/tags/$tested"
  else                          url="https://api.github.com/repos/$repo/releases/latest"; fi

  json="$(curl -fsSL -H 'Accept: application/vnd.github+json' "$url")" \
    || { echo "could not resolve $repo" >&2; exit 1; }

  mapfile -t got < <(printf '%s' "$json" | pick_asset - "$rx")
  version="${got[0]}"; name="${got[1]}"; link="${got[2]}"

  if [[ ! -f "$dl/$name" ]]; then
    echo "  downloading $name"
    curl -fsSL -o "$dl/$name" "$link"
  else
    echo "  cached $name"
  fi

  ex="$work/${repo//\//_}"
  rm -rf "$ex"; mkdir -p "$ex"
  unzip -qo "$dl/$name" -d "$ex"

  if [[ "$kexts" == "OPENCORE" ]]; then
    cp "$ex/X64/EFI/BOOT/BOOTx64.efi" "$efi/BOOT/"
    cp "$ex/X64/EFI/OC/OpenCore.efi"  "$efi/OC/"
    for d in OpenRuntime.efi OpenHfsPlus.efi ResetNvramEntry.efi OpenCanopy.efi; do
      if [[ -f "$ex/X64/EFI/OC/Drivers/$d" ]]; then
        cp "$ex/X64/EFI/OC/Drivers/$d" "$efi/OC/Drivers/"; echo "  + Drivers/$d"
      else
        echo "  ! driver $d not in this release" >&2
      fi
    done
    shell="$(find "$ex" -name OpenShell.efi -print -quit)"
    [[ -n "$shell" ]] && cp "$shell" "$efi/OC/Tools/" && echo "  + Tools/OpenShell.efi"
    # ocvalidate is version-locked to its release - keep them together
    ocv="$(find "$ex" -type f -name ocvalidate -print -quit)"
    [[ -n "$ocv" ]] && cp "$ocv" "$here/" && chmod +x "$here/ocvalidate" && echo "  + tools/ocvalidate"
    ms="$(find "$ex" -type f -name macserial -print -quit)"
    [[ -n "$ms" ]] && cp "$ms" "$here/" && chmod +x "$here/macserial" && echo "  + tools/macserial"
  else
    for k in $kexts; do
      found="$(find "$ex" -type d -name "$k" -not -path '*/Debug/*' -not -path '*PlugIns*' -print -quit)"
      if [[ -z "$found" ]]; then echo "  ! $k not found in $repo $version" >&2; continue; fi
      rm -rf "${efi:?}/OC/Kexts/$k"
      cp -R "$found" "$efi/OC/Kexts/$k"
      echo "  + Kexts/$k"
    done
  fi

  printf '%-42s %-12s %-12s\n' "$repo" "$version" "$tested" >> "$dl/summary.txt"
done

for x in "${excluded[@]}"; do
  if [[ -d "$efi/OC/Kexts/$x" ]]; then
    rm -rf "${efi:?}/OC/Kexts/$x"; echo "removed $x (must stay absent)"
  fi
done

echo ""
echo "--- versions ---"
cat "$dl/summary.txt"
echo ""
echo "Rows where FETCHED and TESTED differ are newer than what this build was"
echo "tested against. Usually fine. Re-run with --tested to pin them."
echo ""
echo "Next: fill in SMBIOS (see EFI/README.md), then ./ocvalidate ../EFI/OC/config.plist"
