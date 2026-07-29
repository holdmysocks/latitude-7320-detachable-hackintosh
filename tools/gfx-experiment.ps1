# gfx-experiment.ps1  -  Iris Xe acceleration experiment (§13)
#
#   .\gfx-experiment.ps1 -Drive Y            apply test 1 (ICL 8A52)
#   .\gfx-experiment.ps1 -Drive Y -Id 8A5C   apply a different platform id
#   .\gfx-experiment.ps1 -Drive Y -Revert    restore the known-good config
#
# Run from Windows with the OpenCore USB stick inserted.

param(
  [Parameter(Mandatory=$true)][string]$Drive,
  [string]$Id = "8A52",
  [switch]$Revert,
  [switch]$NoSpoof,    # control: strip -igfxvesa ONLY, inject nothing
  [switch]$Minimal,    # device-id ONLY - no ig-platform-id, no enable-metal
  [switch]$KeepVesa,   # spoof but LEAVE -igfxvesa in place (safe probe)
  [string]$Plat = "",  # ig-platform-id, e.g. FF05 / 8A5C. Defaults to -Id.
  [switch]$NoWEG       # disable WhateverGreen entirely (it forces VESA on 9A40)
)

$ErrorActionPreference = 'Stop'
$cfg  = "${Drive}:\EFI\OC\config.plist"
$safe = "${Drive}:\EFI\OC\config.KNOWNGOOD.plist"

if (-not (Test-Path $cfg)) { throw "No config.plist at $cfg" }

# ---------- revert ----------
if ($Revert) {
  if (-not (Test-Path $safe)) { throw "No known-good backup found at $safe" }
  Copy-Item $safe $cfg -Force
  Write-Host "Reverted to known-good config (VESA, no IGPU properties)." -ForegroundColor Green
  exit
}

# ---------- one-time known-good snapshot ----------
if (-not (Test-Path $safe)) {
  Copy-Item $cfg $safe -Force
  Write-Host "Saved known-good config to config.KNOWNGOOD.plist" -ForegroundColor DarkGray
} else {
  # always build the test from the known-good, never from a previous test
  Copy-Item $safe $cfg -Force
}

# ---------- build the data blobs ----------
# ig-platform-id is little-endian:  0x8A520000 -> bytes 00 00 52 8A
if ($Plat -eq "") { $Plat = $Id }
$dHi = [Convert]::ToByte($Id.Substring(0,2),16)
$dLo = [Convert]::ToByte($Id.Substring(2,2),16)
$pHi = [Convert]::ToByte($Plat.Substring(0,2),16)
$pLo = [Convert]::ToByte($Plat.Substring(2,2),16)
$platB64 = [Convert]::ToBase64String(@(0,0,$pLo,$pHi))     # 00 00 52 8A
$devB64  = [Convert]::ToBase64String(@($dLo,$dHi,0,0))     # 52 8A 00 00

if ($Minimal) {
  $block = @"
			<key>PciRoot(0x0)/Pci(0x2,0x0)</key>
			<dict>
				<key>device-id</key>
				<data>
				$devB64
				</data>
			</dict>
"@
} else {
  $block = @"
			<key>PciRoot(0x0)/Pci(0x2,0x0)</key>
			<dict>
				<key>AAPL,ig-platform-id</key>
				<data>
				$platB64
				</data>
				<key>device-id</key>
				<data>
				$devB64
				</data>
			</dict>
"@
}

$t = Get-Content $cfg -Raw

if (-not $NoSpoof) {
  # insert the IGPU block ahead of the audio entry (unique anchor)
  $anchor = "`t`t`t<key>PciRoot(0x0)/Pci(0x1f,0x3)</key>"
  if ($t -notmatch [regex]::Escape($anchor)) { throw "Anchor not found - config layout changed." }
  $t = $t.Replace($anchor, ($block.TrimEnd() + "`r`n" + $anchor))
}

# drop -igfxvesa so the framebuffer can attempt to attach,
# unless -KeepVesa: then the spoof is visible in ioreg but VESA still owns
# the display, so the box survives to be inspected.
if (-not $KeepVesa) { $t = $t.Replace(" -igfxvesa", "") }

if ($NoWEG) {
  # flip WhateverGreen's Enabled true -> false
  $re = '(?s)(<string>WhateverGreen\.kext</string>.*?<key>Enabled</key>\s*)<true/>'
  if ($t -notmatch $re) { throw "Could not find WhateverGreen Enabled key." }
  $t = [regex]::Replace($t, $re, '${1}<false/>')
}

[System.IO.File]::WriteAllText($cfg, $t)

Write-Host ""
if ($NoSpoof) {
  Write-Host "CONTROL TEST: -igfxvesa removed, NO DeviceProperties injected." -ForegroundColor Cyan
} else {
  if ($Minimal) { Write-Host "Applied: device-id 0x$Id ONLY" -ForegroundColor Cyan }
  else          { Write-Host "Applied: ig-platform-id 0x${Plat}0000 + device-id 0x$Id" -ForegroundColor Cyan }
  if ($NoWEG)    { Write-Host "WhateverGreen DISABLED." -ForegroundColor Magenta }
  if ($KeepVesa) { Write-Host "-igfxvesa KEPT (safe probe - should boot)." }
  else           { Write-Host "-igfxvesa removed." }
}
Write-Host ""
Write-Host "Recovery: if it black-screens, power off, boot Windows, and run:" -ForegroundColor Yellow
Write-Host "    .\gfx-experiment.ps1 -Drive $Drive -Revert" -ForegroundColor Yellow
Write-Host ""
