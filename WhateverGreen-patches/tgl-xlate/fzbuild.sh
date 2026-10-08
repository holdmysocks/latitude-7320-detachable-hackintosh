#!/bin/zsh
cd "$(dirname "$0")"; M=./mesa
I=(-Ikassert -Istub -Ieu -I$M/src -I$M/src/intel -I$M/include -I$M/src/util -I$M/src/compiler -I$M/src/mesa -DHAVE_PTHREAD -DHAVE_STRUCT_TIMESPEC -DHAVE_TIMESPEC_GET -include inttypes.h -Wno-everything -g -O0 -fno-inline -fsanitize=address,undefined -fno-sanitize-recover=undefined)
[ "$1" = all ] && for f in brw_eu_compact brw_eu_emit brw_eu brw_reg_type brw_eu_util brw_disasm brw_eu_validate; do clang -c $I eu/$f.c -o fz/$f.o; done
clang $I fuzz.c tgl_xlate.c stubs.c fz/*.o -o fuzz && UBSAN_OPTIONS=print_stacktrace=1 ./fuzz "$@" 2>&1 | grep -E "runtime error|ERROR|#[0-9] |accepted" | head -9 | cut -c1-210
