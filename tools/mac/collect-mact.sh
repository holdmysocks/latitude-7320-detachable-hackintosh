#!/bin/bash
# collect-mact.sh  -  [MAC-T] capture everything from the current boot onto the USB.
#
#   sudo bash /Volumes/TGLDEBUG/mac/collect-mact.sh <label>
#     labels used in START-HERE: baseline, step1, step2
#
# Writes /Volumes/TGLDEBUG/results/mact-<label>-<time>/ and prints a short verdict.
# Read-only on the system: it changes nothing on this Mac.

set -uo pipefail
LABEL="${1:-manual}"
USB="$(cd "$(dirname "$0")/.." && pwd)"
[ "$(id -u)" = 0 ] || { echo "Run with sudo."; exit 1; }
OUT="$USB/results/mact-$LABEL-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
cd "$OUT"

echo "Capturing to $OUT ..."
{ sw_vers; uname -a; sysctl -n machdep.cpu.brand_string; nvram boot-args 2>&1;
  echo "kern.msgbuf: $(sysctl -n kern.msgbuf 2>/dev/null)"; } > system.txt

# graphics device and what attached to it
ioreg -lw0 -r -n IGPU  > ioreg-igpu.txt 2>&1
ioreg -lw0 -r -n GFX0 >> ioreg-igpu.txt 2>&1
ioreg -rw0 -c IOFramebuffer > ioreg-framebuffers.txt 2>&1
ioreg -rw0 -c IOAccelerator > ioreg-accel.txt 2>&1

# loaded kexts
kmutil showloaded 2>/dev/null > kexts-all.txt || kextstat > kexts-all.txt
grep -iE 'lilu|whatevergreen|AppleIntel|IOAccelerator|IOGraphics' kexts-all.txt > kexts-graphics.txt

# this boot's log, filtered to Lilu / WhateverGreen / Intel graphics
log show --last boot --style compact \
  --predicate 'eventMessage CONTAINS[c] "igfx" OR eventMessage CONTAINS "Lilu" OR eventMessage CONTAINS "WhateverGreen" OR eventMessage CONTAINS "IGFB" OR eventMessage CONTAINS "[IGPU]" OR sender BEGINSWITH "AppleIntel"' \
  > log-graphics.txt 2>&1

# Lilu/WhateverGreen log via IOLog, and early-boot IOLog output often never reaches
# the unified log. The kernel message buffer is the reliable source.
dmesg > dmesg.txt 2>/dev/null || echo "(dmesg unavailable)" > dmesg.txt
grep -iE 'igfx|whatevergreen|lilu|IGFB|IGPU' dmesg.txt > dmesg-graphics.txt 2>/dev/null

# panic reports macOS has picked up (the Windows harness reads OpenCore's copy; this is the backup channel)
mkdir -p panics
find /Library/Logs/DiagnosticReports -maxdepth 2 \( -name '*.panic' -o -name 'panic-*' \) -mtime -14 -exec cp {} panics/ \; 2>/dev/null
nvram -p 2>/dev/null | grep -i panic > nvram-panic.txt

# one-time: the framebuffer binary for the symbol inventory (HANDOFF-3 task B)
CAP="$USB/kext-capture"
FB=/System/Library/Extensions/AppleIntelICLLPGraphicsFramebuffer.kext
if [ ! -d "$CAP/AppleIntelICLLPGraphicsFramebuffer.kext" ] && [ -d "$FB" ]; then
  mkdir -p "$CAP"
  ditto --norsrc --noextattr "$FB" "$CAP/AppleIntelICLLPGraphicsFramebuffer.kext"
  if [ ! -f "$FB/Contents/MacOS/AppleIntelICLLPGraphicsFramebuffer" ]; then
    # binary lives only in the kernel collection on this OS - take the collection instead (<4 GB for FAT32)
    for kc in /System/Library/KernelCollections/SystemKernelExtensions.kc /System/Library/KernelCollections/BootKernelExtensions.kc; do
      [ -f "$kc" ] && cp "$kc" "$CAP/" 2>/dev/null
    done
  fi
  sw_vers > "$CAP/macos-version.txt"
  echo "Captured the framebuffer kext into $CAP"
fi

# tidy FAT32 metadata
find "$USB/results" "$USB/kext-capture" -name '._*' -delete 2>/dev/null

# which OpenCore booted us, and with what
nvram -p 2>/dev/null | grep -iE 'opencore|boot-path|boot-args' > opencore.txt
ACTUAL_ARGS="$(nvram boot-args 2>/dev/null | cut -f2- | tr -s ' ' | sed 's/ *$//')"
# Take the version from inside the parentheses. A bare [0-9.]+ grep also matches
# the digits in "vit9696", which made every boot look wrong.
WG_VER="$(grep -m1 -oE 'as\.vit9696\.WhateverGreen \([0-9.]+\)' kexts-graphics.txt | sed -E 's/.*\(([0-9.]+)\)/\1/')"
[ -n "$WG_VER" ] || WG_VER=none
EXPECT_ARGS="$(sed -n 's/.*"expectedArgs" *: *"\([^"]*\)".*/\1/p' "$USB/results/current.json" 2>/dev/null | tr -s ' ' | sed 's/ *$//')"
EXPECT_WG="$(sed -n 's/.*"expectedWgVersion" *: *"\([^"]*\)".*/\1/p' "$USB/results/current.json" 2>/dev/null)"

# ---- verdict ----
echo
echo "=============== summary: $LABEL ==============="
if [ -n "$EXPECT_ARGS" ]; then
  if [ "$ACTUAL_ARGS" = "$EXPECT_ARGS" ] && { [ -z "$EXPECT_WG" ] || [ "$WG_VER" = "$EXPECT_WG" ]; }; then
    echo "BOOT SOURCE OK: this boot used the config the Windows harness applied."
  else
    echo "*** WRONG BOOT - THIS RUN TESTED NOTHING ***"
    echo "    expected boot-args: $EXPECT_ARGS"
    echo "    actual   boot-args: $ACTUAL_ARGS"
    echo "    expected WhateverGreen: ${EXPECT_WG:-unknown}   actual: $WG_VER"
    echo "    You almost certainly booted the rescue OpenCore on the USB, or another EFI."
    echo "    Fix: [WIN] .\\tgl-experiment.ps1 -DisarmRescue, then redo this run."
    echo "    Record the run as void: [WIN] .\\tgl-experiment.ps1 -Collect -Outcome void"
  fi
  echo "------------------------------------------------"
fi
echo "boot-args:      $(nvram boot-args 2>/dev/null | cut -f2-)"
echo "ig-platform-id: $(grep -m1 -o '"AAPL,ig-platform-id" = <[0-9a-f]*>' ioreg-igpu.txt || echo none)"
echo "device-id:      $(grep -m1 -o '"device-id" = <[0-9a-f]*>' ioreg-igpu.txt || echo none)"
echo "framebuffer:    $(grep -m1 -oE 'IONDRVFramebuffer|AppleIntelFramebuffer[A-Za-z@0-9]*' ioreg-framebuffers.txt || echo none)"
echo "graphics kexts:"; cut -c1-160 kexts-graphics.txt | head -8 | sed "s/^/    /"
FIRST_TS="$(grep -m1 -oE '^\[ *[0-9]+\.[0-9]+\]' dmesg.txt 2>/dev/null | tr -d '[] ')"
if [ -n "$FIRST_TS" ]; then
  if [ "${FIRST_TS%%.*}" -gt 30 ] 2>/dev/null; then
    echo "dmesg:          WRAPPED - oldest entry is ${FIRST_TS}s into boot, so early-boot"
    echo "                Lilu/WhateverGreen lines are gone. This is expected and cannot be"
    echo "                fixed with msgbuf=: xnu only reads that boot-arg under CONFIG_XNUPOST,"
    echo "                which release kernels do not build. kern.msgbuf stays at"
    echo "                $(sysctl -n kern.msgbuf 2>/dev/null) bytes. Early-boot status must be"
    echo "                reported by panicking, not by logging."
  else
    echo "dmesg:          intact from ${FIRST_TS}s"
  fi
fi
echo "Lilu in kernel buffer: $(grep -c -i 'lilu' dmesg.txt 2>/dev/null) line(s)"
echo "WhateverGreen / tracer lines (kernel buffer + unified log):"
WGLINES="$(cat dmesg-graphics.txt log-graphics.txt 2>/dev/null | grep -E 'unsupported processor|TGL:|RRS:|RWS:|Failing probe|Failed to resolve|unsupported platform' | sed -E 's/^.{0,40}(WhateverGreen|AppleIntel)/\1/' | sort -u | head -15)"
if [ -n "$WGLINES" ]; then
  echo "$WGLINES" | sed 's/^/    /'
else
  echo "    (none found - see dmesg.txt. Early IOLog output can be missing from both"
  echo "     sources, so absence here is not proof that the kext did nothing.)"
fi
echo "panic reports copied: $(ls panics | wc -l | tr -d ' ')"
echo "================================================"
echo "Saved to $OUT"
