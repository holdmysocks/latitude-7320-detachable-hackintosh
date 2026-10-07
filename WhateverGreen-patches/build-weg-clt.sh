#!/bin/bash
# build-weg.sh <source dir> <out dir>  - build WhateverGreen.kext with Command Line Tools only (no Xcode).
# Mirrors the Xcode Release settings of the project (c++17, -O3, kext flags, Lilu 1.7.2 SDK, MacKernelSDK).
set -e
SRC=$(cd "$1" && pwd); OUT=$2; mkdir -p "$OUT/obj"; OUT=$(cd "$OUT" && pwd)
VER=$(grep -m1 "MODULE_VERSION = " "$SRC/WhateverGreen.xcodeproj/project.pbxproj" | sed 's/.*= \(.*\);/\1/')
SDK=$SRC/MacKernelSDK
COMMON=(-target x86_64-apple-macos10.6 -O3 -nostdinc -fno-builtin -fno-common -mkernel -fvisibility=hidden
  -fstrict-aliasing -mmmx -msse -msse2 -msse3 -mfpmath=sse -mssse3 -ftree-vectorize -fno-non-call-exceptions -fno-asynchronous-unwind-tables
  -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT -DMODULE_VERSION=$VER -DPRODUCT_NAME=WhateverGreen
  -I"$SDK/Headers" -I"$SRC/Lilu.kext/Contents/Resources" -I"$SRC/Lilu.kext/Contents/Resources/Headers" -I"$SRC/WhateverGreen" -I"$OUT/obj"
  -Wno-unknown-warning-option -Wno-ossharedptr-misuse -Wno-vla -Wno-deprecated-declarations -Wno-inconsistent-missing-override -Wno-format)
CXX=(-x c++ -std=c++17 -fno-rtti -fno-exceptions -fapple-kext -fcheck-new)
cat > "$OUT/obj/WhateverGreen_info.c" <<INFO
#include <mach/mach_types.h>
extern kern_return_t _start(kmod_info_t *ki, void *data);
extern kern_return_t _stop(kmod_info_t *ki, void *data);
__private_extern__ kern_return_t WhateverGreen_kern_start(kmod_info_t *ki, void *data);
__private_extern__ kern_return_t WhateverGreen_kern_stop(kmod_info_t *ki, void *data);
__attribute__((visibility("default"))) KMOD_EXPLICIT_DECL(as.vit9696.WhateverGreen, "$VER", _start, _stop)
__private_extern__ kmod_start_func_t *_realmain = WhateverGreen_kern_start;
__private_extern__ kmod_stop_func_t *_antimain = WhateverGreen_kern_stop;
__private_extern__ int _kext_apple_cc = __APPLE_CC__ ;
INFO
objs=()
for f in "$SRC"/WhateverGreen/*.cpp "$SRC/Lilu.kext/Contents/Resources/Library/plugin_start.cpp"; do
  o="$OUT/obj/$(basename "${f%.cpp}").o"; clang "${CXX[@]}" "${COMMON[@]}" -c "$f" -o "$o"; objs+=("$o")
done
for f in "$SRC"/WhateverGreen/*.S; do o="$OUT/obj/$(basename "${f%.S}").o"; clang "${COMMON[@]}" -c "$f" -o "$o"; objs+=("$o"); done
clang -x c -std=c11 "${COMMON[@]}" -c "$OUT/obj/WhateverGreen_info.c" -o "$OUT/obj/WhateverGreen_info.o"; objs+=("$OUT/obj/WhateverGreen_info.o")
K="$OUT/WhateverGreen.kext"; rm -rf "$K"; mkdir -p "$K/Contents/MacOS"
clang++ -target x86_64-apple-macos10.6 -O3 -L"$SDK/Library/x86_64" "${objs[@]}" -nostdlib -Xlinker -dead_strip -static -Xlinker -kext -lkmodc++ -lkmod -lcc_kext -lkmod -Xlinker -no_adhoc_codesign -o "$K/Contents/MacOS/WhateverGreen"
strip -x -T "$K/Contents/MacOS/WhateverGreen" 2>/dev/null || strip -x "$K/Contents/MacOS/WhateverGreen"
sed -e "s/\$(MODULE_VERSION)/$VER/g" -e 's/$(EXECUTABLE_NAME)/WhateverGreen/g' -e 's/$(PRODUCT_BUNDLE_IDENTIFIER)/as.vit9696.WhateverGreen/g' -e 's/$(PRODUCT_NAME)/WhateverGreen/g' -e 's/$(MODULE_NAME)/as.vit9696.WhateverGreen/g' -e 's/$(DEVELOPMENT_LANGUAGE)/en/g' -e 's/$(PRODUCT_BUNDLE_PACKAGE_TYPE)/KEXT/g' -e 's/$(PRODUCT_NAME:rfc1034identifier)/WhateverGreen/g' -e 's/$(MODULE_NAME:rfc1034identifier)/as.vit9696.WhateverGreen/g' "$SRC/WhateverGreen/Info.plist" > "$K/Contents/Info.plist"
plutil -lint "$K/Contents/Info.plist" >/dev/null
if grep -q '\$(' "$K/Contents/Info.plist"; then echo "ERROR: unexpanded build variable in Info.plist"; grep -n '\$(' "$K/Contents/Info.plist"; exit 1; fi
codesign --force --sign - --timestamp=none "$K" 2>/dev/null || true
echo "built $K  v$VER  sha256 $(shasum -a 256 "$K/Contents/MacOS/WhateverGreen" | cut -d' ' -f1)"
