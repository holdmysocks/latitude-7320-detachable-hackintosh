#!/bin/bash
# tgl-mac.sh - macOS-side harness for the Latitude 7320 Tiger Lake iGPU experiments ([MAC-T], Tahoe).
# Does what win\tgl-experiment.ps1 does for apply / revert / collect, from macOS. ESP work needs sudo
# (the script re-runs itself with sudo and macOS asks for your password).
#
#   tgl-mac.sh status                      what is live on the ESP, what is running, what is armed
#   tgl-mac.sh gen <experiment> [opts]     only generate results/gen-<experiment>.plist and validate it
#   tgl-mac.sh apply <experiment> [opts]   known-good -> experiment config on the ESP (validated), then reboot
#   tgl-mac.sh collect [keep] [outcome]    after the boot: capture, read panics, put known-good back
#                                          ("collect keep" leaves a surviving experiment config in place)
#   tgl-mac.sh revert                      known-good back on the ESP, nothing else
#   tgl-mac.sh promote                     make the live config the new known-good (keeps the previous as .prev)
#   tgl-mac.sh vesa                        put the VESA base config live (safe fallback, no Intel framebuffer)
#   tgl-mac.sh install-kext 0001|0002|0003|stock  swap WhateverGreen.kext on the ESP
#   tgl-mac.sh install-acpi <name>         copy built/acpi/<name>.aml to EFI/OC/ACPI (e.g. SSDT-DOSI)
#   tgl-mac.sh install-extra <name>        copy built/extra/<name>.kext to EFI/OC/Kexts (e.g. BrightnessKeys)
#   tgl-mac.sh fblog [since]               Apple framebuffer driver log of earlier boots (persists even after a dark boot)
#   tgl-mac.sh mapstate                    decode the 0003 shim's state record (NVRAM + IORegistry)
#   tgl-mac.sh arm-rescue | disarm-rescue  make the stick's rescue OpenCore bootable / not
#   tgl-mac.sh list                        experiments and options (from make-experiment.py)
#
# Experiments and options are defined in make-experiment.py (A, A-sam, A-cam0, A-nocdc, A-static,
# selftest, alive, stop=N, fn=N, fnret=N; --dvmt-mb=60 --plat=HEX --dev=HEX).
set -u
STICK=/Volumes/TGLDEBUG
HERE=$STICK/mac
RES=$STICK/results
# The ESP is the EFI partition of the internal disk. Disk numbers change between boots (the stick can be disk0).
find_esp(){
  local d p
  for d in $(diskutil list internal physical 2>/dev/null | awk '/^\/dev\/disk/{print $1}'); do
    p=$(diskutil list "$d" | awk '$2=="EFI"{print $NF; exit}')
    [ -n "$p" ] && { echo "$p"; return; }
  done
}
ESP_DEV=$(find_esp)
GEN=$HERE/make-experiment.py
OCV=$HERE/ocvalidate
RUNS=$RES/mac-runs.csv
CUR=$RES/mac-current.json
SEEN=$RES/mac-seen-panics.txt
BACKUP_KG=$(ls -d "$STICK"/backup/ESP-EFI-*/EFI/OC/config.KNOWNGOOD.plist 2>/dev/null | tail -1)
SHA_0001=4829f51bcc5f652109c64aa7738a553a34b6157f15209cbb496c4f1b4f871f89
SHA_0002=b3103adf6c90ed55cb0d2e92e1e8c5e9c3bcf986948c126293f7d6224b6b7d72
SHA_0003=5d01c8f99f321171e6e909196a80b0d15d455c24d140053e2e6b71f136b0c924
SHA_0003B=bf982c3b7344fb2f83dc7105672352fc18cdb0660e4895446ba28b9f40de817f
SHA_0003C=0fe97e3599e260f8be90e3decebd67d65093ab2849fcf3c2cfe7c3d346d045be
SHA_0003D=00f701526c378409b08a6d767faa4af136c284e92fd53bcb7a76adaedcbab54e
SHA_0003E=908211d72d183d87baeea8ede2d8c7bfaedf78b18e186fe9dade89aa821d31b5
SHA_0003F=281b4dfaa110efa1accecebaa242a5d8f72b11cbb1ed145a9ef611e91161591a
SHA_0003G=b9c4eca75b372b099f21baf441460c03592800b4c7c15687a858b01fc5289649
SHA_0003H=3d6fb3e4bd911a6b9cfde5ee8b41570e50e3f9a7ceb43109b651e3d8193ca224
SHA_0003I=c3a3005693ee905fcb5543358838ce789d004b8342af67506bed1765f77623e2
SHA_0003J=42c7bc3e46e125a64de071e7e4782c479b97ff8d170c53fdec0ba5ea7ba3035b
SHA_0003K=ae83820ababb1eb04ce1e590ec145e338fb8e51bf7adc939629eb76bf098c20a
SHA_0003L=179055bc9817044aba57ff5ec9aa6a29c25761e4bd0907834d14818f84fce3aa
SHA_0003M=467d5c7e32c11423fc29bd950b108c9cba44e9d244de5f08df4713b6834b4fb0
SHA_0003N=9ff60641e69ff97c07b49db264e0fed705a586935b09157cb5e6a1ff535951be
SHA_0003O=e60cb5472d7742f9d1b46cdc5e3c0cd42903b2519b162962de67c7c8733648ab
SHA_0003P=3691757ffee6246e801c72697b1b00fee4eebb7107283d255dc01831cc029e00
SHA_0003Q=54316b4c874662dc80489c8961462ff1a208537a32e7e3bb8250ecabc0ece829
SHA_0003S=3de7190c5c321b24e3671051cbd533596faaf2b98bf1cda2a9b9c5cee5b4395a
SHA_0003V=c91b158a49dfc7ff4f86357cc64ed7280e9e1a3765df3839316f31dd32d3f107
SHA_0003X=d22c6d004808110a6ee3db13804bce7a60447a8fd87e1540e9370e0d51433f44
SHA_0004G=2c345fb5c501a4dc4f87446bbbbe7d4b3b8b3baa9ae7c63e43657d34e6a2d153
SHA_0004F=27ccf76cb22b8c1b5f5b681953f87aef126ede39087c886d4915c3953eff9cac
SHA_0004E=ff22a31af8828575e2cc5527897c7c4f6ac65ca88863604dc43cd0addd0acb64
SHA_0004D=5d288720d9a5432b50db764ec105a4a0aacd921a7949568be9d46285a98841ed
SHA_0004C=e4490610a9dad4ce5957bd413c9e922d62f3e43c4a7cfa3b962e5a0685ced17b
SHA_0004B=b59e008bfa675d36535c83ecfb26b68186f4178afa95e6468e7ad2d72e61209b
SHA_0004A=60e3e2b382b71262973aa9102c6c3939d51e6128b0d0ca4e0b60883743108deb
SHA_0003Z=b3ebf1b26314d16a9875373e66de9d2e02664e009c127f77a2d9cbc9e50de91f
SHA_0003Y=a2f061ba24d0d52e706633b9fd574cd9a1b95a79cfee0c238a285a32053c99c4
SHA_0003T=02a7f9735077560f7acc0c76d7dc3616679c4edd07b2ca81c30055e82f8ad458
STATEFILE=/Users/Shared/tgl-map-state.bin
NVKEY=4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:tgl-map-state

say(){ printf '%s\n' "$*"; }
die(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
sha(){ shasum -a 256 "$1" | cut -d' ' -f1; }
ts(){ date +%Y%m%d-%H%M%S; }
need_root(){ [ "$(id -u)" = 0 ] || exec sudo KEEP="${KEEP:-0}" FORCE="${FORCE:-0}" -- "$0" "$@"; }

[ -d "$STICK" ] || die "$STICK is not mounted"
[ -f "$GEN" ] || die "$GEN missing"

esp_mount(){
  [ -n "$ESP_DEV" ] || die "could not find the internal disk's EFI partition"
  case "$(diskutil info "$ESP_DEV" | awk -F': +' '/Volume Name/{print $2}')" in TGLDEBUG) die "refusing: $ESP_DEV is the TGLDEBUG stick, not the internal ESP";; esac
  local mp; mp=$(diskutil info "$ESP_DEV" | awk -F': +' '/Mount Point/{print $2}'); case "$mp" in /*) ;; *) mp="";; esac
  if [ -z "$mp" ]; then
    diskutil mount "$ESP_DEV" >/dev/null || die "cannot mount $ESP_DEV (are you root?)"
    mp=$(diskutil info "$ESP_DEV" | awk -F': +' '/Mount Point/{print $2}'); case "$mp" in /*) ;; *) mp="";; esac
  fi
  [ -n "$mp" ] || die "ESP ($ESP_DEV) is not mounted"
  ESP=$mp; OC=$mp/EFI/OC; LIVE=$OC/config.plist; KG=$OC/config.KNOWNGOOD.plist; BASE=$OC/config.BASE-VESA.plist
  # BASE is the VESA config every experiment is generated from; KNOWNGOOD is what revert/collect restore
  # (since 2026-10-07 the promoted working config, experiment K).
  [ -f "$BASE" ] || { [ -n "$BACKUP_KG" ] && cp "$BACKUP_KG" "$BASE"; }
  [ -f "$LIVE" ] || die "no EFI/OC/config.plist on $ESP"
  if [ ! -f "$KG" ]; then
    [ -n "$BACKUP_KG" ] || die "no config.KNOWNGOOD.plist on the ESP and no backup copy on the stick"
    say "No config.KNOWNGOOD.plist on the ESP; copying the stick's backup ($BACKUP_KG)"
    cp "$BACKUP_KG" "$KG" || die "copy failed"
  fi
}

verify_block(){ python3 - "$1" <<'PY'
import plistlib,sys
p=plistlib.load(open(sys.argv[1],'rb'))
nv=p['NVRAM']['Add']['7C436110-AB2A-4BBB-A880-FE41995C9F82']
print("  boot-args   :", nv.get('boot-args'))
dp=p['DeviceProperties']['Add'].get("PciRoot(0x0)/Pci(0x2,0x0)")
print("  IGPU        :", ' '.join('%s=%s'%(k,v.hex()) for k,v in dp.items()) if dp else "no DeviceProperties injected (stock)")
print("  Kernel/Block:", [(b['Identifier'],b['Strategy']) for b in p['Kernel'].get('Block',[]) if b.get('Enabled')] or 'none')
print("  Kernel/Patch:", [k.get('Comment') for k in p['Kernel'].get('Patch',[]) if k.get('Enabled')] or 'none')
PY
}
plist_args(){ python3 -c "import plistlib,sys;print(plistlib.load(open(sys.argv[1],'rb'))['NVRAM']['Add']['7C436110-AB2A-4BBB-A880-FE41995C9F82']['boot-args'])" "$1"; }
running_args(){ nvram boot-args 2>/dev/null | cut -f2-; }
kg_args(){ plist_args "${KG:-$BACKUP_KG}"; }
weg_label(){
  local b="$1/Contents/MacOS/WhateverGreen"; [ -f "$b" ] || { echo "missing"; return; }
  local s v; s=$(sha "$b"); v=$(defaults read "$1/Contents/Info.plist" CFBundleVersion 2>/dev/null)
  case "$s" in
    "$SHA_0001") echo "0001 register-tracer build (v$v)";;
    "$SHA_0002") echo "0002 self-test + function-tracer build (v$v)";;
    "$SHA_0003") echo "0003 register-map build, FIRST revision (side effects always on; reset in run B) (v$v)";;
    "$SHA_0003B") echo "0003b register-map build (feature mask; superseded by 0003c) (v$v)";;
    "$SHA_0003C") echo "0003c register-map build (superseded by 0003d) (v$v)";;
    "$SHA_0003D") echo "0003d register-map build (superseded by 0003e) (v$v)";;
    "$SHA_0003E") echo "0003e register-map build (TRANS_CLK_SEL fix; superseded by 0003f) (v$v)";;
    "$SHA_0003F") echo "0003f register-map build (snapshot published in the hook; reset in run F3) (v$v)";;
    "$SHA_0003G") echo "0003g register-map build (snapshot to NVRAM from a thread call; reset in run F4) (v$v)";;
    "$SHA_0003H") echo "0003h register-map build (snapshot to file; superseded by 0003i) (v$v)";;
    "$SHA_0003I") echo "0003i register-map build (first working display, experiment K) (v$v)";;
    "$SHA_0003J") echo "0003j register-map build (rescaling backlight; max 23 % on seamless boots) (v$v)";;
    "$SHA_0003K") echo "0003k register-map build (0003j + backlight scale from SFUSE_STRAP) (v$v)";;
    "$SHA_0003L") echo "0003l register-map build (0003k + igfxtglblmax backlight level range) (v$v)";;
    "$SHA_0003M") echo "0003m register-map build (0003l + zero backlight duty passed through, level restored on PWM enable) (v$v)";;
    "$SHA_0003N") echo "0003n register-map build (0003m + backlight duty capped below 100 percent) (v$v)";;
    "$SHA_0003O") echo "0003o register-map build (transcoder clock released only after the transcoder stopped; optional disk trace) (v$v)";;
    "$SHA_0003P") echo "0003p register-map build (0003o, TRANS_CLK_SEL_A no longer cleared after port disable) (v$v)";;
    "$SHA_0003Q") echo "0003q register-map build (0003p + paced display power-down, igfxtglmap 0x20000) (v$v)";;
    "$SHA_0003S") echo "0003s register-map build (no transcoder clean-up after port disable; trace and pacing options off by default) (v$v)";;
    "$SHA_0003V") echo "0003v register-map build (0003s cleaned up: no duty cap, no pacing option) (v$v)";;
    "$SHA_0003X") echo "0003x accelerator-work build (0003v + igfxtglss subslice patch for AppleIntelICLGraphics + GT fuse probe) (v$v)";;
    "$SHA_0003Y") echo "0003y accelerator-work build (0003x + igfxtglcsb Gen12 context status buffer reader, log in /Users/Shared/tgl-csb.bin) (v$v)";;
    "$SHA_0003Z") echo "0003z accelerator-work build (0003y with a 6-entry context status buffer) (v$v)";;
    "$SHA_0004A") echo "0004a accelerator-work build (0003z + igfxtglhang: batch and shader kernels of a GPU hang to /Users/Shared/tgl-hang.bin) (v$v)";;
    "$SHA_0004B") echo "0004b accelerator-work build (0004a + igfxtglxl: Gen11->Gen12 shader translation at batch submission, log /Users/Shared/tgl-xlate.bin) (v$v)";;
    "$SHA_0004C") echo "0004c accelerator-work build (0004b + translator: inserted waits, branches, growth into padding, 3DSTATE_HS fix) (v$v)";;
    "$SHA_0004D") echo "0004d accelerator-work build (0004c + exact register-usage tracking in the translator) (v$v)";;
    "$SHA_0004E") echo "0004e accelerator-work build (0004d + translator: jmpi, register descriptors, kernels up to 36 KB) (v$v)";;
    "$SHA_0004F") echo "0004f accelerator-work build (0004e + never touches stolen memory or the PCI hole; translator: goto/join, indirect addressing, padding, acc1, 100 KB kernels) (v$v)";;
    "$SHA_0004G") echo "0004g accelerator-work build (0004f + shaders up to 700 KB, pixel-shader dispatch modes, igfxtglres resolve skip) (v$v)";;
    "$SHA_0003T") echo "0003t DIAGNOSTIC build (0003v + GT fuse probe, igfxtglmap 0x80000) (v$v)";;
    *) echo "v$v, sha ${s:0:12} (stock or unknown)";;
  esac
}
weg_running_matches(){
  local want run; want=$(dwarfdump --uuid "$1/Contents/MacOS/WhateverGreen" 2>/dev/null | awk '{print $2}')
  run=$(kextstat 2>/dev/null | awk '/WhateverGreen/{print $8}')
  if [ -z "$run" ]; then echo "NO - WhateverGreen is NOT LOADED in this boot"; elif [ "$run" = "$want" ]; then echo "yes ($run)"; else echo "NO - running $run, ESP has $want (not rebooted since install, or booted from the rescue stick)"; fi
}
weg_tag(){ local s; s=$(sha "$1/Contents/MacOS/WhateverGreen" 2>/dev/null); case "$s" in "$SHA_0001") echo 0001;; "$SHA_0002") echo 0002;; "$SHA_0003") echo 0003a;; "$SHA_0003B") echo 0003b;; "$SHA_0003C") echo 0003c;; "$SHA_0003D") echo 0003d;; "$SHA_0003E") echo 0003e;; "$SHA_0003F") echo 0003f;; "$SHA_0003G") echo 0003g;; "$SHA_0003H") echo 0003h;; "$SHA_0003I") echo 0003i;; "$SHA_0003J") echo 0003j;; "$SHA_0003K") echo 0003k;; "$SHA_0003L") echo 0003l;; "$SHA_0003M") echo 0003m;; "$SHA_0003N") echo 0003n;; "$SHA_0003O") echo 0003o;; "$SHA_0003P") echo 0003p;; "$SHA_0003Q") echo 0003q;; "$SHA_0003S") echo 0003s;; "$SHA_0003V") echo 0003;; "$SHA_0003X") echo 0003x;; "$SHA_0003Y") echo 0003y;; "$SHA_0003Z") echo 0003z;; "$SHA_0004A") echo 0004a;; "$SHA_0004B") echo 0004b;; "$SHA_0004C") echo 0004c;; "$SHA_0004D") echo 0004d;; "$SHA_0004E") echo 0004e;; "$SHA_0004F") echo 0004f;; "$SHA_0004G") echo 0004g;; "$SHA_0003T") echo 0003t;; *) echo other;; esac; }
cur_get(){ [ -f "$CUR" ] && python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2],''))" "$CUR" "$1"; }
runs_add(){ # time,label,experiment,expected_args,outcome,notes
  [ -f "$RUNS" ] || echo '"time","label","experiment","expected_args","outcome","notes"' > "$RUNS"
  printf '"%s","%s","%s","%s","%s","%s"\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$1" "$2" "$3" "$4" "$5" >> "$RUNS"
}

cmd_list(){ python3 "$GEN"; }

cmd_status(){
  say "== Running system (this boot)"
  say "  boot-args (nvram)   : $(running_args)"
  say "  WhateverGreen loaded: $(kextstat 2>/dev/null | awk '/WhateverGreen/{print $6, $7}')"
  say "  framebuffer classes : $(ioreg -l -w0 2>/dev/null | grep -oE 'class (IONDRVFramebuffer|AppleIntelFramebuffer|AppleIntelFramebufferController)' | sort | uniq -c | tr -s ' ' | tr '\n' ';')"
  say "  IGPU platform-id    : $(ioreg -rn IGPU@2 -d1 2>/dev/null | grep -oE '"AAPL,ig-platform-id" = <[0-9a-f]+>')"
  say "== Stick"
  say "  rescue OpenCore     : $([ -d "$STICK/EFI" ] && echo 'ARMED (stick is bootable; firmware will prefer it)' || echo 'disarmed')"
  say "  current experiment  : $([ -f "$CUR" ] && cat "$CUR" || echo none)"
  if [ "$(id -u)" = 0 ]; then
    esp_mount
    say "== ESP ($ESP)"
    if [ "$(sha "$LIVE")" = "$(sha "$KG")" ]; then say "  config.plist        : IDENTICAL to config.KNOWNGOOD.plist"; else say "  config.plist        : DIFFERS from config.KNOWNGOOD.plist (experiment or leftover)"; fi
    verify_block "$LIVE"
    say "  WhateverGreen.kext  : $(weg_label "$OC/Kexts/WhateverGreen.kext")"
    say "  running = ESP kext  : $(weg_running_matches "$OC/Kexts/WhateverGreen.kext")"
    say "  panic files on ESP  :"; ls -la "$ESP"/panic-*.txt 2>/dev/null | sed 's/^/    /' || true; [ -z "$(ls "$ESP"/panic-*.txt 2>/dev/null)" ] && say "    none"
  else
    say "== ESP: run with sudo to see the live config and panic files"
  fi
}

cmd_gen(){
  local exp=${1:-}; [ -n "$exp" ] || die "gen needs an experiment name (tgl-mac.sh list)"; shift
  local src=${BASE:-$BACKUP_KG}; [ -f "$src" ] || die "no base config to start from"
  local out="$RES/gen-${exp//=/_}.plist"
  python3 "$GEN" "$src" "$out" "$exp" "$@" || die "generation failed"
  "$OCV" "$out" 2>&1 | tail -1
  "$OCV" "$out" 2>&1 | grep -q "No issues found" || die "ocvalidate rejected $out"
}

cmd_apply(){
  need_root apply "$@"
  local exp=${1:-}; [ -n "$exp" ] || die "apply needs an experiment name (tgl-mac.sh list)"; shift
  esp_mount
  if [ -f "$CUR" ] && [ "$(cur_get state)" = "applied" ]; then die "experiment '$(cur_get label)' is still pending. Run: sudo $0 collect <outcome>   (or revert)"; fi
  [ "$(sha "$LIVE")" = "$(sha "$KG")" ] || die "live config.plist differs from config.KNOWNGOOD.plist. Run: sudo $0 revert   then apply again."
  [ -f "$BASE" ] || die "no config.BASE-VESA.plist on the ESP to generate from"
  local tag; tag=$(weg_tag "$OC/Kexts/WhateverGreen.kext")
  case "$exp" in
    B|B-*|C|C-*|D|D-*|E|E-*|F|F-*|F2|F2-*|F3|F4|F5|K|K-*|M|M-*|N|P|P2|Q|R|S|G|G-*|G2|G3|H) [ "$tag" = 0003 ] || die "'$exp' needs the current 0003v WhateverGreen build on the ESP (have: $tag). Run: sudo $0 install-kext 0003";;
    GA12) [ "$tag" = 0004g ] || die "'$exp' needs the 0004g accelerator-work build on the ESP (have: $tag). Run: sudo $0 install-kext 0004g";;
    GA11) [ "$tag" = 0004f ] || die "'$exp' needs the 0004f accelerator-work build on the ESP (have: $tag). Run: sudo $0 install-kext 0004f";;
    GA10) [ "$tag" = 0004e ] || die "'$exp' needs the 0004e accelerator-work build on the ESP (have: $tag). Run: sudo $0 install-kext 0004e";;
    GA9) [ "$tag" = 0004d ] || die "'$exp' needs the 0004d accelerator-work build on the ESP (have: $tag). Run: sudo $0 install-kext 0004d";;
    GA8) [ "$tag" = 0004c ] || die "'$exp' needs the 0004c accelerator-work build on the ESP (have: $tag). Run: sudo $0 install-kext 0004c";;
    GA7) [ "$tag" = 0004b ] || die "'$exp' needs the 0004b accelerator-work build on the ESP (have: $tag). Run: sudo $0 install-kext 0004b";;
    GA6) [ "$tag" = 0004a ] || die "'$exp' needs the 0004a accelerator-work build on the ESP (have: $tag). Run: sudo $0 install-kext 0004a";;
    GA4|GA5) [ "$tag" = 0003z ] || die "'$exp' needs the 0003z accelerator-work build on the ESP (have: $tag). Run: sudo $0 install-kext 0003z";;
    GA3) [ "$tag" = 0003y ] || die "'$exp' needs the 0003y accelerator-work build on the ESP (have: $tag). Run: sudo $0 install-kext 0003y";;
    GA1|GA2) [ "$tag" = 0003x ] || die "'$exp' needs the 0003x accelerator-work build on the ESP (have: $tag). Run: sudo $0 install-kext 0003x";;
    selftest|alive|fn=*|fnret=*) [ "$tag" = 0002 ] || [ "$tag" = 0003 ] || die "'$exp' needs the 0002 WhateverGreen build on the ESP (have: $tag). Run: sudo $0 install-kext 0002";;
    stop=*) [ "$tag" = 0001 ] || [ "$tag" = 0002 ] || [ "$tag" = 0003 ] || die "'$exp' needs the 0001 or 0002 build (have: $tag)";;
  esac
  case "$(weg_running_matches "$OC/Kexts/WhateverGreen.kext")" in yes*) ;; *) say "note: the kext on the ESP is not the one running now (same toolchain as the 0003 build that is proven to load).";; esac
  { [ "$exp" != P ] && [ "$exp" != P2 ] && [ "$exp" != Q ] && [ "$exp" != R ] && [ "$exp" != S ] && [ "$exp" != GA1 ] && [ "$exp" != GA2 ] && [ "$exp" != GA3 ] && [ "$exp" != GA4 ] && [ "$exp" != GA5 ] && [ "$exp" != GA6 ] && [ "$exp" != GA7 ] && [ "$exp" != GA8 ] && [ "$exp" != GA9 ] && [ "$exp" != GA10 ] && [ "$exp" != GA11 ] && [ "$exp" != GA12 ]; } || [ -f "$OC/ACPI/SSDT-DOSI.aml" ] || die "experiment P needs SSDT-DOSI.aml on the ESP. Run: sudo $0 install-acpi SSDT-DOSI"
  case "$exp" in N|P) ;; *) false;; esac && { [ -f "$OC/Kexts/BrightnessKeys.kext/Contents/Info.plist" ] || die "experiment $exp needs BrightnessKeys.kext on the ESP. Run: sudo $0 install-extra BrightnessKeys"; }
  [ "$exp" != __never__ ] || die "experiment N needs BrightnessKeys.kext on the ESP. Run: sudo $0 install-extra BrightnessKeys"
  local tmp; tmp=$(mktemp /tmp/tgl-exp.XXXXXX)
  python3 "$GEN" "$BASE" "$tmp" "$exp" "$@" || die "generation failed"
  "$OCV" "$tmp" 2>&1 | grep -q "No issues found" || { "$OCV" "$tmp"; die "ocvalidate rejected the generated config; nothing written"; }
  cp "$tmp" "$LIVE" || die "could not write $LIVE"; rm -f "$tmp"
  find "$OC" -name '._*' -delete 2>/dev/null
  nvram -d "$NVKEY" 2>/dev/null
  [ -f "$STATEFILE" ] && { mv "$STATEFILE" "$RES/old-tgl-map-state-$(ts).bin"; say "(moved a previous $STATEFILE to results/)"; }
  local label="${exp//=/_}-$(ts)"; local expected; expected=$(plist_args "$LIVE")
  python3 - "$CUR" "$label" "$exp" "$expected" "$(kg_args)" "$tag" "$*" <<'PY'
import json,sys,time
json.dump({"label":sys.argv[2],"experiment":sys.argv[3],"expected_args":sys.argv[4],"knowngood_args":sys.argv[5],
           "weg_build":sys.argv[6],"options":sys.argv[7],"applied":time.strftime("%Y-%m-%dT%H:%M:%S"),"state":"applied"},open(sys.argv[1],"w"),indent=1)
PY
  runs_add "$label" "$exp" "$expected" "applied" "$*"
  say ""; say "Applied '$exp' to $LIVE. Verify block (re-read from the ESP):"; verify_block "$LIVE"
  say "  WhateverGreen.kext  : $(weg_label "$OC/Kexts/WhateverGreen.kext")"
  say "  rescue on stick     : $([ -d "$STICK/EFI" ] && echo ARMED || echo 'DISARMED  (after a reset the picker will re-run this experiment in 10 s unless you press an arrow key)')"
  say ""
  say "Next:  reboot.  At the OpenCore picker choose macOS and WATCH the screen (photo any panic text)."
  say "       Then, back in macOS (experiment survived, or known-good after a crash):"
  say "         sudo $0 collect            (asks for the outcome if this boot is not the experiment)"
}

cmd_revert(){
  need_root revert "$@"
  esp_mount
  cp "$KG" "$LIVE" || die "copy failed"; find "$OC" -name '._*' -delete 2>/dev/null
  say "Reverted. Live config:"; verify_block "$LIVE"
  [ "$(sha "$LIVE")" = "$(sha "$KG")" ] || die "live still differs from known-good?!"
  if [ -f "$CUR" ]; then python3 - "$CUR" <<'PY'
import json,sys; d=json.load(open(sys.argv[1])); d["state"]="reverted"; json.dump(d,open(sys.argv[1],"w"),indent=1)
PY
  fi
}

cmd_collect(){
  need_root collect "$@"
  if [ "${1:-}" = keep ]; then KEEP=1; shift; fi
  local outcome=${1:-}
  esp_mount
  local label; label=$(cur_get label); [ -n "$label" ] || label="adhoc"
  local exp; exp=$(cur_get experiment); local expected; expected=$(cur_get expected_args); local applied; applied=$(cur_get applied)
  local out="$RES/mac-$label-collect-$(ts)"; mkdir -p "$out/panics"
  local running; running=$(running_args)
  say "== Boot source check"
  say "  running boot-args : $running"
  say "  experiment args   : ${expected:-?}"
  local source
  if [ -n "$expected" ] && [ "$running" = "$expected" ]; then source=experiment; say "  => THIS BOOT IS THE EXPERIMENT. It survived."; outcome=${outcome:-booted}
  elif [ "$running" = "$(kg_args)" ]; then source=knowngood; say "  => this is a KNOWN-GOOD boot (rescue stick, or reverted config). Report what the experiment boot did."
  else source=unknown; say "  => UNEXPECTED boot-args; treat this capture with care."; fi
  { say "label=$label"; say "experiment=$exp"; say "applied=$applied"; say "expected_args=$expected"; say "running_args=$running"; say "boot_source=$source"; sw_vers; } > "$out/summary.txt"
  nvram -p > "$out/nvram.txt" 2>&1
  kextstat > "$out/kexts-all.txt" 2>&1; grep -iE "lilu|whatever|intel|graphics|framebuffer" "$out/kexts-all.txt" > "$out/kexts-graphics.txt"
  ioreg -rn IGPU@2 -l -w0 > "$out/ioreg-igpu.txt" 2>&1
  ioreg -c IOFramebuffer -r -l -w0 > "$out/ioreg-framebuffers.txt" 2>&1
  ioreg -c IOAccelerator -r -l -w0 > "$out/ioreg-accel.txt" 2>&1
  system_profiler SPDisplaysDataType > "$out/displays.txt" 2>&1
  log show --last boot --predicate 'eventMessage CONTAINS "IGFB" OR eventMessage CONTAINS "igfx" OR eventMessage CONTAINS "Lilu" OR eventMessage CONTAINS "WhateverGreen" OR eventMessage CONTAINS "DVMT" OR eventMessage CONTAINS "stolen" OR eventMessage CONTAINS "AppleIntel" OR eventMessage CONTAINS "lilucpu"' --style compact > "$out/log-graphics.txt" 2>&1
  dmesg > "$out/dmesg.txt" 2>&1
  # panics: ESP root (OpenCore ApplePanic), macOS reports, NVRAM
  touch "$SEEN"; local n=0
  for f in "$ESP"/panic-*.txt; do [ -f "$f" ] || continue; grep -qxF "$(basename "$f")" "$SEEN" || { cp "$f" "$out/panics/"; echo "$(basename "$f")" >> "$SEEN"; n=$((n+1)); }; done
  find /Library/Logs/DiagnosticReports -maxdepth 1 \( -name '*.panic' -o -name 'Kernel*' \) -newer "$CUR" -exec cp {} "$out/panics/" \; 2>/dev/null
  nvram -p 2>/dev/null | grep -iE "panic" > "$out/panics/nvram-panic.txt" || true
  # OpenCore logs, crash reports and any persisted unified-log lines since the experiment was applied
  mkdir -p "$out/opencore-logs" "$out/diagnostics"
  find "$ESP" -maxdepth 1 -name 'opencore-*.txt' -newer "$CUR" -exec cp {} "$out/opencore-logs/" \; 2>/dev/null
  find /Library/Logs/DiagnosticReports -maxdepth 1 -type f -newer "$CUR" -exec cp {} "$out/diagnostics/" \; 2>/dev/null
  local since; since=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['applied'].replace('T',' '))" "$CUR" 2>/dev/null || true)
  [ -n "$since" ] && log show --start "$since" --predicate 'process == "kernel" AND (eventMessage CONTAINS "IGFB" OR eventMessage CONTAINS "igfx" OR eventMessage CONTAINS "DVMT" OR eventMessage CONTAINS "Lilu" OR eventMessage CONTAINS "WhateverGreen" OR eventMessage CONTAINS "AppleIntel" OR eventMessage CONTAINS "lilucpu")' --style compact > "$out/log-graphics-since-apply.txt" 2>&1
  [ -n "$since" ] && /usr/bin/log show --start "$since" --predicate 'process == "kernel" AND eventMessage CONTAINS "IGFB"' --style compact > "$out/log-igfb-since-apply.txt" 2>&1
  nvram "$NVKEY" > "$out/nvram-tgl-map-state.txt" 2>/dev/null || rm -f "$out/nvram-tgl-map-state.txt"
  [ -f "$STATEFILE" ] && cp "$STATEFILE" "$out/tgl-map-state.bin"
  ioreg -l -w0 2>/dev/null | grep -m1 '"tgl-map-state"' > "$out/ioreg-tgl-map-state.txt" || rm -f "$out/ioreg-tgl-map-state.txt"
  { [ -f "$out/tgl-map-state.bin" ] && python3 "$HERE/decode-tglmap.py" "$out/tgl-map-state.bin"; [ -f "$out/nvram-tgl-map-state.txt" ] && python3 "$HERE/decode-tglmap.py" "$out/nvram-tgl-map-state.txt"; [ -f "$out/ioreg-tgl-map-state.txt" ] && python3 "$HERE/decode-tglmap.py" "$out/ioreg-tgl-map-state.txt"; } > "$out/tgl-map-state-decoded.txt" 2>&1
  for f in "$out"/opencore-logs/opencore-*.txt; do [ -f "$f" ] || continue; grep -aE "Block|Exclude|AppleIntelICLGraphics|boot-args|Prelink|KC: |Kext|panic|Lilu|Whatever" "$f" | head -60 > "$f.summary.txt"; done
  say "== Panics"; say "  new panic-*.txt on ESP: $n"; say "  OpenCore logs since apply: $(ls "$out/opencore-logs" 2>/dev/null | grep -v summary | tr '\n' ' ')"; say "  crash reports since apply: $(ls "$out/diagnostics" 2>/dev/null | tr '\n' ' ')"; ls "$out/panics" | sed 's/^/    /'
  for f in "$out"/panics/panic-*.txt; do [ -f "$f" ] || continue; say "  --- $(basename "$f") (first lines)"; grep -aE "igfx TGL|TGL: |panic\(|Kernel version|stopped before|fn stopped|selftest|alive" "$f" | head -12 | sed 's/^/    /'; done
  if [ -s "$out/log-igfb-since-apply.txt" ]; then
    say "== Apple framebuffer driver, since the experiment was applied (errors, link training, modeset result)"
    grep -E "IGFB" "$out/log-igfb-since-apply.txt" | grep -E "ERROR|LINK_TRAINING|Lighting up|Modeset|modeset|Boot pipe|stolen|Starting FB|is not enabled|fOnline" | sed -E 's/^[0-9-]+ ([0-9:.]+) .*\(AppleIntelICLLPGraphicsFramebuffer\) /\1 /' | awk '{k=$0; sub(/^[0-9:.]+ /,"",k); c[k]++; if(c[k]<=2) print "  " substr($0,1,170)}' | head -60
  fi
  if [ -s "$out/tgl-map-state-decoded.txt" ]; then say "== Register-map shim state (full decode in tgl-map-state-decoded.txt)"; sed -n '/hardware snapshots/,$p' "$out/tgl-map-state-decoded.txt" | sed 's/^/  /' | head -60; else say "== Register-map shim state: no record (file, NVRAM or IORegistry)"; fi
  say "== Graphics log lines (this boot)"; grep -E "IGFB|igfx|DVMT|lilucpu|WhateverGreen" "$out/log-graphics.txt" | head -40 | sed 's/^/  /'
  say "  framebuffer classes: $(ioreg -l -w0 2>/dev/null | grep -oE 'class (IONDRVFramebuffer|AppleIntelFramebuffer)' | sort | uniq -c | tr -s ' ' | tr '\n' ';')"
  if [ -z "$outcome" ]; then
    say ""; say "What did the EXPERIMENT boot do?"
    say "  r = reset (black screen, Dell logo came back by itself)"
    say "  p = panic text was visible on screen (photo!)"
    say "  h = hang (frozen; nothing from that boot in the log)"
    say "  d = dark: screen went black or stayed black, but the machine seemed to stay on"
    say "  v = void (that boot did not run the experiment)"
    read -r -p "outcome [r/p/h/d/v]: " ans
    case "$ans" in r) outcome=reset;; p) outcome=panic-seen;; h) outcome=hang;; d) outcome=blackscreen;; v) outcome=void;; *) outcome=unknown;; esac
  fi
  echo "outcome=$outcome" >> "$out/summary.txt"
  runs_add "$label" "$exp" "$expected" "$outcome" "capture=$(basename "$out") panics=$n source=$source"
  if [ -f "$CUR" ]; then python3 - "$CUR" "$outcome" "$out" <<'PY'
import json,sys; d=json.load(open(sys.argv[1])); d["state"]="collected"; d["outcome"]=sys.argv[2]; d["capture"]=sys.argv[3]; json.dump(d,open(sys.argv[1],"w"),indent=1)
PY
  fi
  if [ "${KEEP:-0}" = 1 ] && [ "$source" = experiment ]; then
    say "KEEP=1: leaving the experiment config live (you are running on it now)."
  else
    cp "$KG" "$LIVE"; find "$OC" -name '._*' -delete 2>/dev/null; say "== Known-good config restored on the ESP."
  fi
  say "== Saved: $out"; say "== Run recorded in $RUNS as: $label / $exp / $outcome"
}

cmd_install_kext(){
  need_root install-kext "$@"
  local which=${1:-}; local src
  case "$which" in
    0001) src=$STICK/built/WhateverGreen.kext;;
    0002) src=$STICK/built/next/WhateverGreen.kext;;
    0003) src=$STICK/built/0003v/WhateverGreen.kext;;
    0003s) src=$STICK/built/0003s/WhateverGreen.kext;;
    0003x) src=$STICK/built/0003x/WhateverGreen.kext;;
    0003y) src=$STICK/built/0003y/WhateverGreen.kext;;
    0003z) src=$STICK/built/0003z/WhateverGreen.kext;;
    0004a) src=$STICK/built/0004a/WhateverGreen.kext;;
    0004b) src=$STICK/built/0004b/WhateverGreen.kext;;
    0004c) src=$STICK/built/0004c/WhateverGreen.kext;;
    0004d) src=$STICK/built/0004d/WhateverGreen.kext;;
    0004e) src=$STICK/built/0004e/WhateverGreen.kext;;
    0004f) src=$STICK/built/0004f/WhateverGreen.kext;;
    0004g) src=$STICK/built/0004g/WhateverGreen.kext;;
    0003q) src=$STICK/built/0003q/WhateverGreen.kext;;
    0003p) src=$STICK/built/0003p/WhateverGreen.kext;;
    0003o) src=$STICK/built/0003o/WhateverGreen.kext;;
    0003n) src=$STICK/built/0003n/WhateverGreen.kext;;
    0003m) src=$STICK/built/0003m/WhateverGreen.kext;;
    0003t) src=$STICK/built/0003t/WhateverGreen.kext;;
    0003l) src=$STICK/built/0003l/WhateverGreen.kext;;
    0003k) src=$STICK/built/0003k/WhateverGreen.kext;;
    0003j) src=$STICK/built/0003j/WhateverGreen.kext;;
    0003i) src=$STICK/built/0003i/WhateverGreen.kext;;
    stock) src=$STICK/backup/stock-kexts/WhateverGreen.kext;;
    *) die "install-kext 0001 | 0002 | 0003 | 0003i | stock";;
  esac
  [ -f "$src/Contents/MacOS/WhateverGreen" ] || die "$src has no binary"
  esp_mount
  rm -rf "$OC/Kexts/WhateverGreen.kext"; cp -R "$src" "$OC/Kexts/WhateverGreen.kext" || die "copy failed"
  find "$OC/Kexts" -name '._*' -delete 2>/dev/null
  say "ESP WhateverGreen.kext is now: $(weg_label "$OC/Kexts/WhateverGreen.kext")"
}

cmd_fblog(){
  local since=${1:-}; [ -n "$since" ] || since=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['applied'].replace('T',' '))" "$CUR" 2>/dev/null)
  [ -n "$since" ] || die "fblog needs a start time, e.g. '2026-10-07 08:36:00'"
  /usr/bin/log show --start "$since" --predicate 'process == "kernel" AND eventMessage CONTAINS "IGFB"' --style compact | sed -E 's/^[0-9-]+ ([0-9:.]+) .*\(AppleIntelICLLPGraphicsFramebuffer\) /\1 /' | grep -vE "Sagv point|h24_maxplanes|\\[VDT"
}
cmd_mapstate(){ python3 "$HERE/decode-tglmap.py"; }
cmd_promote(){
  need_root promote "$@"
  esp_mount
  "$OCV" "$LIVE" 2>&1 | grep -q "No issues found" || die "ocvalidate rejects the live config; not promoting"
  cp "$KG" "$OC/config.KNOWNGOOD.prev.plist"; cp "$LIVE" "$KG"; find "$OC" -name '._*' -delete 2>/dev/null
  say "Promoted the live config to config.KNOWNGOOD.plist (previous one kept as config.KNOWNGOOD.prev.plist):"; verify_block "$KG"
}
cmd_vesa(){
  need_root vesa "$@"
  esp_mount; cp "$BASE" "$LIVE"; say "Live config is now the VESA base (config.BASE-VESA.plist):"; verify_block "$LIVE"
}
cmd_install_extra(){
  need_root install-extra "$@"
  local name=${1:-}; local src=$STICK/built/extra/$name.kext
  [ -f "$src/Contents/Info.plist" ] || die "no $src (available: $(ls "$STICK/built/extra" 2>/dev/null | tr '\n' ' '))"
  esp_mount
  rm -rf "$OC/Kexts/$name.kext"; cp -R "$src" "$OC/Kexts/$name.kext" || die "copy failed"
  find "$OC/Kexts" -name '._*' -delete 2>/dev/null
  say "Installed $name.kext $(defaults read "$OC/Kexts/$name.kext/Contents/Info.plist" CFBundleVersion) into EFI/OC/Kexts (inactive until a config lists it)."
}
cmd_install_acpi(){
  need_root install-acpi "$@"
  local name=${1:-}; local src=$STICK/built/acpi/$name.aml
  [ -f "$src" ] || die "no $src (available: $(ls "$STICK/built/acpi" 2>/dev/null | grep aml | tr '\n' ' '))"
  esp_mount
  cp "$src" "$OC/ACPI/$name.aml" || die "copy failed"; rm -f "$OC/ACPI/._$name.aml"
  say "Installed $name.aml into EFI/OC/ACPI (inactive until a config lists it)."
}
cmd_arm(){
  [ -d "$STICK/EFI" ] && { say "already armed"; return; }
  [ -d "$STICK/EFI-RESCUE" ] || die "no EFI-RESCUE folder on the stick"
  mv "$STICK/EFI-RESCUE" "$STICK/EFI" || die "rename failed"
  say "Rescue ARMED: the stick now boots the known-good OpenCore. Config check: $([ "$(sha "$STICK/EFI/OC/config.plist")" = "$(sha "$BACKUP_KG")" ] && echo 'identical to the known-good config' || echo 'DIFFERS from the backup known-good config')"
}
cmd_disarm(){
  [ -d "$STICK/EFI" ] || { say "already disarmed"; return; }
  mv "$STICK/EFI" "$STICK/EFI-RESCUE" || die "rename failed"; say "Rescue disarmed."
}

cmd=${1:-}; shift || true
case "$cmd" in
  status) cmd_status "$@";; gen) cmd_gen "$@";; apply) cmd_apply "$@";; collect) cmd_collect "$@";;
  revert) cmd_revert "$@";; install-kext) cmd_install_kext "$@";; arm-rescue) cmd_arm;; disarm-rescue) cmd_disarm;;
  install-extra) cmd_install_extra "$@";;
  install-acpi) cmd_install_acpi "$@";;
  fblog) cmd_fblog "$@";; mapstate) cmd_mapstate;; promote) cmd_promote "$@";; vesa) cmd_vesa "$@";;
  list) cmd_list;;
  *) sed -n '2,20p' "$0"; exit 2;;
esac
