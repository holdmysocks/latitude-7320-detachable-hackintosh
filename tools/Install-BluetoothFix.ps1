# Install-BluetoothFix.ps1
#   Retrofits IntelBTPatcher.kext into an EFI that predates it, and upgrades
#   IntelBluetoothFirmware to the lshbluesky fork.
#
#   .\Install-BluetoothFix.ps1 -Drive S      # internal ESP (mount it first!)
#   .\Install-BluetoothFix.ps1 -Drive Y      # rescue USB
#
# Run elevated. For the internal ESP:  mountvol S: /s   before, /d after.
#
# YOU PROBABLY DO NOT NEED THIS. The config.plist in this repository already
# carries IntelBTPatcher in the correct load position, and fetch-components.ps1
# downloads both Bluetooth kexts. This script exists for retrofitting an EFI
# built before the fix - do both your internal ESP and your rescue USB, so the
# rescue stick stays a true fallback.
#
# Background: docs/05b-wifi-and-bluetooth.md

param(
  [Parameter(Mandatory=$true)][string]$Drive,
  [string]$KextSource
)

$ErrorActionPreference = 'Stop'

$oc  = "${Drive}:\EFI\OC"
$cfg = "$oc\config.plist"
$src = if ($KextSource) { $KextSource } else { Join-Path (Split-Path $PSScriptRoot -Parent) 'EFI\OC\Kexts' }

if (-not (Test-Path $cfg)) { throw "No config.plist at $cfg. Is the ESP mounted?  mountvol ${Drive}: /s" }

Copy-Item $cfg "$cfg.bak-bt" -Force
Write-Host "Backed up config.plist -> config.plist.bak-bt" -ForegroundColor DarkGray

# --- copy kexts -------------------------------------------------------
foreach ($k in 'IntelBluetoothFirmware.kext','IntelBTPatcher.kext') {
  $from = Join-Path $src $k
  if (-not (Test-Path $from)) {
    throw "$k not found in $src. Run .\fetch-components.ps1 first, or pass -KextSource <folder>."
  }
  $dst = Join-Path "$oc\Kexts" $k
  if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
  Copy-Item $from $dst -Recurse -Force
  Write-Host "  installed $k" -ForegroundColor Green
}

# --- add IntelBTPatcher to Kernel > Add, immediately before BlueToolFixup
$t = [System.IO.File]::ReadAllText($cfg)

if ($t -match 'IntelBTPatcher\.kext') {
  Write-Host "IntelBTPatcher already present in config - skipping insert." -ForegroundColor Yellow
} else {
  $T3 = "`t`t`t"; $T4 = "`t`t`t`t"
  $nl = if ($t -match "`r`n") { "`r`n" } else { "`n" }
  $entry = (@(
    "$T3<dict>"
    "$T4<key>Arch</key>"
    "$T4<string>x86_64</string>"
    "$T4<key>BundlePath</key>"
    "$T4<string>IntelBTPatcher.kext</string>"
    "$T4<key>Comment</key>"
    "$T4<string>REQUIRED on Monterey+ - initialises bluetoothd. Needs Lilu 1.6.2+</string>"
    "$T4<key>Enabled</key>"
    "$T4<true/>"
    "$T4<key>ExecutablePath</key>"
    "$T4<string>Contents/MacOS/IntelBTPatcher</string>"
    "$T4<key>MaxKernel</key>"
    "$T4<string></string>"
    "$T4<key>MinKernel</key>"
    "$T4<string></string>"
    "$T4<key>PlistPath</key>"
    "$T4<string>Contents/Info.plist</string>"
    "$T3</dict>"
  ) -join $nl) + $nl

  # anchor: the <dict> that opens the BlueToolFixup entry
  $anchor = (@(
    "$T3<dict>"
    "$T4<key>Arch</key>"
    "$T4<string>x86_64</string>"
    "$T4<key>BundlePath</key>"
    "$T4<string>BlueToolFixup.kext</string>"
  ) -join $nl)

  if (-not $t.Contains($anchor)) {
    throw "Could not find the BlueToolFixup entry to anchor against. Add IntelBTPatcher.kext manually in ProperTree, ordered AFTER IntelBluetoothFirmware and BEFORE BlueToolFixup."
  }

  # IndexOf + splice, not Replace: Replace would insert at every match
  $i = $t.IndexOf($anchor)
  $t = $t.Substring(0, $i) + $entry + $t.Substring($i)
  [System.IO.File]::WriteAllText($cfg, $t)
  Write-Host "  added IntelBTPatcher.kext to Kernel > Add" -ForegroundColor Green
}

Write-Host ""
Write-Host "Load order must be: Lilu -> IntelBluetoothFirmware -> IntelBTPatcher -> BlueToolFixup" -ForegroundColor Cyan
Write-Host "Validate with:  .\ocvalidate.exe $cfg"
Write-Host ""
Write-Host "Then clear the stale controller cache - this is NOT a full NVRAM reset:" -ForegroundColor Yellow
Write-Host "    sudo nvram -d bluetoothActiveControllerInfo"
Write-Host "    sudo nvram -d bluetoothInternalControllerInfo"
Write-Host "See docs/05b-wifi-and-bluetooth.md section 10.4." -ForegroundColor DarkGray
