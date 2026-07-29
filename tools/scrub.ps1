# scrub.ps1 - redact personal identifiers from captured dumps
#
#   .\scrub.ps1 -Path ..\research\data -Recurse          # apply redactions
#   .\scrub.ps1 -Path ..\research\data -Recurse -Check   # audit only, no writes
#
# Every dump in research/ was passed through this before being committed.
#
# The redaction MAP is deliberately not in this file. A scrubbing script that
# hardcodes the strings it is scrubbing republishes exactly what it set out to
# remove. Instead the map lives in scrub-map.local.psd1, which is gitignored;
# copy scrub-map.example.psd1 to that name and fill in your own values.
#
# -Check needs no map. It sweeps for the *shapes* of the identifiers that
# matter - Apple serials, MAC addresses in every encoding, non-zero SMBIOS
# UUIDs - so it is a meaningful check for anyone, on any repo, including this
# one after the fact.

param(
  [Parameter(Mandatory=$true)][string]$Path,
  [switch]$Recurse,
  [switch]$Check
)

$ErrorActionPreference = 'Stop'

$textExt = '.txt','.log','.json','.plist','.md','.dsl','.ps1','.sh'
$targets = if (Test-Path $Path -PathType Container) {
  Get-ChildItem $Path -File -Recurse:$Recurse |
    Where-Object { $_.Extension -in $textExt -and $_.FullName -notmatch '\\\.git\\' -and $_.Name -notlike 'scrub*' }
} else {
  Get-Item $Path
}

# ---------------------------------------------------------------- audit mode
if ($Check) {
  $patterns = [ordered]@{
    'Apple serial (C02/C17/FVF... 12 char)' = '\b(?:C0[0-9]|C1[0-9]|F[VC]F|DGK|G8V)[A-Z0-9]{8,9}\b'
    'MLB (17 char board serial)'            = '\b[A-Z0-9]{5}[0-9]{6}[A-Z0-9]{6}\b'
    'MAC address, colon or dash form'       = '\b(?:[0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}\b'
    'MAC address, bare hex in <>'           = '<[0-9a-fA-F]{12}>'
    'non-zero SMBIOS/platform UUID'         = '(?!00000000-0000-0000-0000-000000000000)\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b'
    'IPv4 address'                          = '\b(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)\b'
    'email address'                         = '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
    # Built by concatenation so that grepping this repo for the retired
    # namespace returns nothing, including from the checker itself.
    'retired GitHub namespace'              = ('Foiler' + '25')
  }

  $found = 0
  foreach ($f in $targets) {
    $t = [System.IO.File]::ReadAllText($f.FullName)
    foreach ($name in $patterns.Keys) {
      $m = [regex]::Matches($t, $patterns[$name])
      if ($m.Count) {
        $found++
        Write-Host ("{0}" -f $f.FullName) -ForegroundColor Yellow
        Write-Host ("    {0}: {1}" -f $name, (($m | ForEach-Object { $_.Value } | Sort-Object -Unique | Select-Object -First 6) -join ', ')) -ForegroundColor DarkYellow
      }
    }
  }
  if ($found) {
    Write-Host "`n$found pattern hit(s). Review each - some are false positives" -ForegroundColor Red
    Write-Host "(bundle version strings look like IPv4; APFS volume UUIDs are not PII)." -ForegroundColor DarkGray
    exit 1
  }
  Write-Host "`nNo identifier-shaped strings found." -ForegroundColor Green
  exit 0
}

# ---------------------------------------------------------------- apply mode
$mapFile = Join-Path $PSScriptRoot 'scrub-map.local.psd1'
if (-not (Test-Path $mapFile)) {
  throw "No scrub-map.local.psd1 next to this script. Copy scrub-map.example.psd1 to that name and fill in the values for your machine."
}
$map = Import-PowerShellDataFile $mapFile

# Longest keys first, so a short pattern cannot strand a fragment of a longer one.
$keys = $map.Keys | Sort-Object { $_.Length } -Descending

$dirty = 0
foreach ($f in $targets) {
  $t = [System.IO.File]::ReadAllText($f.FullName)
  $orig = $t
  $hits = @()
  foreach ($k in $keys) {
    if ($t.Contains($k)) { $hits += $map[$k]; $t = $t.Replace($k, $map[$k]) }
  }
  if ($t -ne $orig) {
    $dirty++
    [System.IO.File]::WriteAllText($f.FullName, $t)
    Write-Host ("scrubbed {0}  ->  {1}" -f $f.FullName, (($hits | Sort-Object -Unique) -join ', ')) -ForegroundColor Yellow
  }
}
Write-Host "`n$dirty file(s) scrubbed. Now run with -Check." -ForegroundColor Green
