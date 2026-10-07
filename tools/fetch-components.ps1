# fetch-components.ps1 - download OpenCore and the kexts into EFI/
#
#   .\fetch-components.ps1              # newest release of each project
#   .\fetch-components.ps1 -Tested      # the exact versions this build was tested on
#   .\fetch-components.ps1 -KeepZips    # leave the downloads in tools/_downloads
#
# Nothing third-party is committed to this repository, so this script is how
# EFI/ becomes bootable. It resolves each project's GitHub release, picks the
# RELEASE asset, and unpacks the kexts and drivers into place.
#
# It prints the version it actually fetched for every component and warns when
# that differs from the tested set, so a drifting upstream is visible rather
# than silent.
#
# Run from anywhere; paths are resolved relative to this script.

param(
  [switch]$Tested,
  [switch]$KeepZips
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$root  = Split-Path $PSScriptRoot -Parent
$efi   = Join-Path $root 'EFI'
$dl    = Join-Path $PSScriptRoot '_downloads'
$work  = Join-Path $dl '_extract'

# repo, tested version, asset regex, and what to take out of the archive
$components = @(
  @{ Repo='acidanthera/OpenCorePkg';            Tested='1.0.7';  Asset='^OpenCore-.*-RELEASE\.zip$'; Kind='opencore' }
  @{ Repo='acidanthera/Lilu';                   Tested='1.7.2';  Asset='RELEASE\.zip$'; Kexts='Lilu.kext' }
  @{ Repo='acidanthera/VirtualSMC';             Tested='1.3.7';  Asset='RELEASE\.zip$'; Kexts='VirtualSMC.kext','SMCProcessor.kext','SMCBatteryManager.kext','SMCDellSensors.kext' }
  @{ Repo='acidanthera/WhateverGreen';          Tested='1.7.0';  Asset='RELEASE\.zip$'; Kexts='WhateverGreen.kext' }
  @{ Repo='acidanthera/NVMeFix';                Tested='1.1.3';  Asset='RELEASE\.zip$'; Kexts='NVMeFix.kext' }
  @{ Repo='acidanthera/BrightnessKeys';                Tested='1.0.3';  Asset='RELEASE\.zip$'; Kexts='BrightnessKeys.kext' }
  @{ Repo='acidanthera/BrcmPatchRAM';           Tested='2.7.2';  Asset='RELEASE\.zip$'; Kexts='BlueToolFixup.kext' }
  @{ Repo='acidanthera/VoodooPS2';              Tested='2.3.7';  Asset='RELEASE\.zip$'; Kexts='VoodooPS2Controller.kext' }
  @{ Repo='1Revenger1/ECEnabler';               Tested='1.0.6';  Asset='RELEASE\.zip$'; Kexts='ECEnabler.kext' }
  @{ Repo='USBToolBox/kext';                    Tested='1.2.0';  Asset='\.zip$';        Kexts='USBToolBox.kext' }
  @{ Repo='OpenIntelWireless/itlwm';            Tested='2.3.0';  Asset='itlwm.*\.zip$'; Kexts='itlwm.kext' }
  @{ Repo='lshbluesky/IntelBluetoothFirmware';  Tested='2.5.1';  Asset='\.zip$';        Kexts='IntelBluetoothFirmware.kext','IntelBTPatcher.kext' }
)

# Deliberately NOT fetched, and why. See EFI/OC/Kexts/KEXTS.md.
#   IntelBluetoothInjector.kext - Big Sur and earlier only; harmful on Monterey+
#   AirportItlwm.kext           - no Tahoe build exists; use itlwm + HeliPort
#   AppleALC.kext               - no HDA codec on this machine to inject into
$excluded = 'IntelBluetoothInjector.kext','AirportItlwm.kext'

New-Item -ItemType Directory -Force -Path $dl, $work, "$efi\OC\Kexts", "$efi\OC\Drivers", "$efi\OC\Tools", "$efi\BOOT" | Out-Null

function Get-Release($repo, $tag) {
  $url = if ($tag) { "https://api.github.com/repos/$repo/releases/tags/$tag" }
         else       { "https://api.github.com/repos/$repo/releases/latest" }
  try {
    Invoke-RestMethod -Uri $url -Headers @{ 'User-Agent'='fetch-components'; 'Accept'='application/vnd.github+json' }
  } catch {
    throw "Could not resolve $repo $(if($tag){"tag $tag"}else{'latest release'}): $($_.Exception.Message)"
  }
}

$summary = @()

foreach ($c in $components) {
  $tag = if ($Tested) { $c.Tested } else { $null }
  Write-Host "`n=== $($c.Repo) ===" -ForegroundColor Cyan

  $rel = Get-Release $c.Repo $tag
  $version = $rel.tag_name
  $asset = $rel.assets | Where-Object { $_.name -match $c.Asset } | Select-Object -First 1
  if (-not $asset) {
    # -Tested asked for a tag whose assets are named differently; fall back to any zip
    $asset = $rel.assets | Where-Object { $_.name -match '\.zip$' } | Select-Object -First 1
  }
  if (-not $asset) { throw "No usable asset in $($c.Repo) $version. Assets: $(($rel.assets.name) -join ', ')" }

  $zip = Join-Path $dl $asset.name
  if (-not (Test-Path $zip)) {
    Write-Host "  downloading $($asset.name)"
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing
  } else {
    Write-Host "  cached $($asset.name)" -ForegroundColor DarkGray
  }

  $ex = Join-Path $work ($c.Repo -replace '/','_')
  if (Test-Path $ex) { Remove-Item $ex -Recurse -Force }
  Expand-Archive -Path $zip -DestinationPath $ex -Force

  if ($c.Kind -eq 'opencore') {
    $oc = Join-Path $ex 'X64\EFI'
    if (-not (Test-Path $oc)) { throw "Unexpected OpenCore archive layout under $ex" }
    Copy-Item "$oc\BOOT\BOOTx64.efi"   "$efi\BOOT\"      -Force
    Copy-Item "$oc\OC\OpenCore.efi"    "$efi\OC\"        -Force
    foreach ($d in 'OpenRuntime.efi','OpenHfsPlus.efi','ResetNvramEntry.efi','OpenCanopy.efi') {
      $p = Join-Path "$oc\OC\Drivers" $d
      if (Test-Path $p) { Copy-Item $p "$efi\OC\Drivers\" -Force; Write-Host "  + Drivers\$d" -ForegroundColor Green }
      else { Write-Warning "  driver $d not in this OpenCore release" }
    }
    $shell = Get-ChildItem $ex -Recurse -Filter 'OpenShell.efi' | Select-Object -First 1
    if ($shell) { Copy-Item $shell.FullName "$efi\OC\Tools\" -Force; Write-Host "  + Tools\OpenShell.efi" -ForegroundColor Green }
    # ocvalidate is version-locked to the release it ships with - keep them together
    $ocv = Get-ChildItem $ex -Recurse -Filter 'ocvalidate.exe' | Select-Object -First 1
    if ($ocv) { Copy-Item $ocv.FullName $PSScriptRoot -Force; Write-Host "  + tools\ocvalidate.exe" -ForegroundColor Green }
    $ms = Get-ChildItem $ex -Recurse -Filter 'macserial.exe' | Select-Object -First 1
    if ($ms) { Copy-Item $ms.FullName $PSScriptRoot -Force; Write-Host "  + tools\macserial.exe" -ForegroundColor Green }
  }
  else {
    foreach ($k in $c.Kexts) {
      $found = Get-ChildItem $ex -Recurse -Directory -Filter $k |
               Where-Object { $_.FullName -notmatch '\\Debug\\' -and $_.FullName -notmatch 'PlugIns' } |
               Select-Object -First 1
      if (-not $found) { Write-Warning "  $k not found in $($c.Repo) $version - check KEXTS.md"; continue }
      $dest = Join-Path "$efi\OC\Kexts" $k
      if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
      Copy-Item $found.FullName $dest -Recurse -Force
      Write-Host "  + Kexts\$k" -ForegroundColor Green
    }
  }

  $drift = ($version -notmatch [regex]::Escape($c.Tested))
  $summary += [pscustomobject]@{ Component=$c.Repo; Fetched=$version; Tested=$c.Tested; Drift=$(if($drift){'yes'}else{''}) }
}

# Anything harmful that rode along in an archive
foreach ($x in $excluded) {
  $p = Join-Path "$efi\OC\Kexts" $x
  if (Test-Path $p) { Remove-Item $p -Recurse -Force; Write-Host "removed $x (must stay absent)" -ForegroundColor Magenta }
}

if (-not $KeepZips) { Remove-Item $dl -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host "`n--- versions ---" -ForegroundColor Cyan
$summary | Format-Table -AutoSize
if ($summary.Drift -contains 'yes') {
  Write-Host "Components marked 'drift' are newer than the versions this build was" -ForegroundColor Yellow
  Write-Host "tested against. Usually fine. Re-run with -Tested to pin them." -ForegroundColor Yellow
}

Write-Host "`nNext:" -ForegroundColor Cyan
Write-Host "  .\Setup-SMBIOS.ps1                     fill in serial / MLB / UUID / ROM"
Write-Host "  .\ocvalidate.exe ..\EFI\OC\config.plist"
