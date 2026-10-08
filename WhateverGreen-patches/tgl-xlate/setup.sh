#!/bin/bash
# setup.sh - fetch the Mesa sources the translator is built on and lay out ./eu.
# Mesa 23.3.6 (MIT licence), sparse clone of the Intel compiler and what it includes. Nothing of Mesa is in this repo.
set -e
cd "$(dirname "$0")"
if [ ! -d mesa ]; then
  git clone -q --depth 1 --branch mesa-23.3.6 --filter=blob:none --sparse https://gitlab.freedesktop.org/mesa/mesa.git mesa
  (cd mesa && git sparse-checkout set --no-cone 'src/intel/compiler/*' 'src/intel/dev/*' 'src/util/*' 'include/*' 'src/compiler/*' 'src/mesa/main/*' 'src/c11/*' 'src/intel/common/*')
fi
mkdir -p eu
C=mesa/src/intel/compiler
cp $C/brw_inst.h $C/brw_eu_compact.c $C/brw_disasm.c $C/brw_eu.c $C/brw_eu.h $C/brw_reg.h $C/brw_reg_type.c $C/brw_reg_type.h \
   $C/brw_isa_info.h $C/brw_eu_defines.h $C/brw_disasm_info.h $C/brw_gfx_ver_enum.h $C/brw_eu_validate.c $C/brw_eu_emit.c $C/brw_eu_util.c eu/
cp eu-stubs/brw_compiler.h eu-stubs/brw_shader.h eu/
# Apple's compiler writes acc1 as a three-source destination; Mesa's emitter asserts acc0
(cd eu && patch -p4 -s < ../mesa-brw_eu_emit-acc1.patch)
echo "ready: ./build.sh builds the host tool g11to12; build-weg2.sh <WhateverGreen source> <out> builds the kext"
