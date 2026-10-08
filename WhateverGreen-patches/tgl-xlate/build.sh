#!/bin/zsh
# build.sh - build the g11to12 host tool against the Mesa checkout made by setup.sh.
cd "$(dirname "$0")"; M=./mesa
I=(-Istub -Ieu -I$M/src -I$M/src/intel -I$M/include -I$M/src/util -I$M/src/compiler -I$M/src/mesa -DHAVE_PTHREAD -DHAVE_STRUCT_TIMESPEC -DHAVE_TIMESPEC_GET -include inttypes.h -Wno-everything)
for f in eu/*.c; do clang -c $I $f -o ${f%.c}.o || exit 1; done
clang -g $I g11to12.c tgl_xlate.c stubs.c dbg.c eu/*.o -o g11to12
