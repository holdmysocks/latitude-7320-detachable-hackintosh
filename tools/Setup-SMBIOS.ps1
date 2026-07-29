# Setup-SMBIOS.ps1 - personalise config.plist for this machine
#
#   .\Setup-SMBIOS.ps1                 # patch ..\EFI\OC\config.plist in the repo
#   .\Setup-SMBIOS.ps1 -Drive Y        # patch Y:\EFI\OC\config.plist (USB stick)
#   .\Setup-SMBIOS.ps1 -Drive S        # patch the internal ESP (mountvol S: /s first!)
#   .\Setup-SMBIOS.ps1 -Mac AABBCCDDEEFF   # supply the Wi-Fi MAC by hand
#
# Run elevated. Replaces the four placeholders in PlatformInfo > Generic:
#
#   SystemSerialNumber   CHANGE-ME-SERIAL
#   MLB                  CHANGE-ME-MLB
#   SystemUUID           00000000-0000-0000-0000-000000000000
#   ROM                  ESIzRFVm  (= 11:22:33:44:55:66)
#
# Do this before first boot even if you never intend to sign in to iCloud.
# Placeholders boot fine but produce confusing iServices failures later, and a
# duplicated ROM is worse than a wrong one.
#
# This merges the old Setup-Phase1.ps1 and Setup-Phase2.ps1, which were
# identical.

param(
  [string]$Drive,
  [string]$Mac,
  [string]$Model = 'MacBookPro16,2'
)

$ErrorActionPreference = 'Stop'

$cfg = if ($Drive) { "${Drive}:\EFI\OC\config.plist" }
       else        { Join-Path (Split-Path $PSScriptRoot -Parent) 'EFI\OC\config.plist' }

if (-not (Test-Path $cfg)) {
  if ($Drive) { throw "No config.plist at $cfg. Is the ESP mounted?  mountvol ${Drive}: /s" }
  throw "No config.plist at $cfg"
}

$ms  = Join-Path $PSScriptRoot 'macserial.exe'
$ocv = Join-Path $PSScriptRoot 'ocvalidate.exe'
if (-not (Test-Path $ms)) { throw "macserial.exe not found in tools\. Run .\fetch-components.ps1 first." }

Write-Host "config : $cfg" -ForegroundColor DarkGray
Copy-Item $cfg "$cfg.bak" -Force
Write-Host "Backed up to config.plist.bak" -ForegroundColor DarkGray

# --- 1. Wi-Fi MAC -> ROM ------------------------------------------------
if (-not $Mac) {
  $nic = Get-NetAdapter | Where-Object { $_.InterfaceDescription -match 'AX201|Wi-Fi 6' } | Select-Object -First 1
  if (-not $nic) {
    throw "Could not find the AX201 adapter. Run 'Get-NetAdapter', then pass it: -Mac AABBCCDDEEFF"
  }
  $Mac = $nic.MacAddress
  Write-Host "AX201 MAC : $Mac  ($($nic.Name))" -ForegroundColor Cyan
}
$Mac = ($Mac -replace '[-:.]', '').ToUpper()
if ($Mac.Length -ne 12 -or $Mac -notmatch '^[0-9A-F]{12}$') { throw "MAC '$Mac' is not 12 hex digits." }
$romB64 = [Convert]::ToBase64String( (0..5 | ForEach-Object { [Convert]::ToByte($Mac.Substring($_*2,2),16) }) )

# --- 2. Serial + MLB from macserial -------------------------------------
$out  = & $ms --generate --model $Model --num 1
$line = ($out | Where-Object { $_ -match '\|' } | Select-Object -First 1)
if (-not $line) { throw "macserial produced no output. Run it manually: macserial.exe --generate --model $Model --num 1" }
$serial = ($line -split '\|')[0].Trim()
$mlb    = ($line -split '\|')[1].Trim()
$uuid   = [guid]::NewGuid().ToString().ToUpper()

Write-Host "Model     : $Model"
Write-Host "Serial    : $serial"
Write-Host "MLB       : $mlb"
Write-Host "UUID      : $uuid"

# --- 3. Patch the plist by literal substitution --------------------------
$t = [System.IO.File]::ReadAllText($cfg)
$t = $t.Replace('CHANGE-ME-MLB',    $mlb)
$t = $t.Replace('CHANGE-ME-SERIAL', $serial)
$t = $t.Replace('00000000-0000-0000-0000-000000000000', $uuid)
$t = $t.Replace('ESIzRFVm',         $romB64)
[System.IO.File]::WriteAllText($cfg, $t)

# --- 4. Verify no placeholders survived ----------------------------------
$leftover = Select-String -Path $cfg -Pattern 'CHANGE-ME|ESIzRFVm|00000000-0000-0000-0000'
if ($leftover) {
  Write-Host "WARNING: placeholders remain:" -ForegroundColor Red
  $leftover
} else {
  Write-Host "All placeholders replaced." -ForegroundColor Green
}

# --- 5. Validate ----------------------------------------------------------
if (Test-Path $ocv) {
  Write-Host "`n--- ocvalidate ---" -ForegroundColor Yellow
  & $ocv $cfg
} else {
  Write-Host "`nocvalidate.exe not in tools\ - skipping validation." -ForegroundColor DarkYellow
}

Write-Host "`nThe patched config now contains a real MAC address." -ForegroundColor Yellow
Write-Host "Do not commit it, and do not publish it. .gitignore covers config.plist.bak;" -ForegroundColor Yellow
Write-Host "the config itself is tracked, so 'git checkout EFI/OC/config.plist' before" -ForegroundColor Yellow
Write-Host "you push if you patched the copy inside the repo." -ForegroundColor Yellow
Write-Host ""
Write-Host "Next: format a USB stick FAT32/GPT and copy the EFI folder to its root." -ForegroundColor Cyan
