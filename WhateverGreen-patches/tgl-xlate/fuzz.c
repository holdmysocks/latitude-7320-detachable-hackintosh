/* fuzz - feed arbitrary and mutated bytes to the translator built with the kernel's assert behaviour. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include "tgl_xlate.h"
int main(int argc, char **argv)
{
   static uint8_t seed[24][8192], buf[8192], out[8192 + 4096]; int slen[24], ns = 0;
   for (int i = 1; i < argc && ns < 24; i++) { FILE *f = fopen(argv[i], "rb"); if (!f) continue; slen[ns] = (int)fread(seed[ns], 1, 8192, f); fclose(f); ns++; }
   unsigned long ok = 0, rej = 0; srandom(12345);
   for (long it = 0; it < 400000; it++) {
      int mode = it % 4;
      if (mode == 0 || !ns) for (int i = 0; i < 1024; i++) buf[i] = (uint8_t)random();
      else { int s = random() % ns; memcpy(buf, seed[s], 8192); int flips = mode == 1 ? 1 : mode == 2 ? 4 : 32;
             for (int k = 0; k < flips; k++) buf[random() % (slen[s] > 16 ? slen[s] : 320)] ^= (uint8_t)(1 << (random() % 8)); }
      struct tgl_xlate_info info;
      if (tgl_xlate_kernel(buf, 8192, out, &info) > 0) ok++; else rej++;
   }
   printf("accepted %lu rejected %lu\n", ok, rej);
   return 0;
}
