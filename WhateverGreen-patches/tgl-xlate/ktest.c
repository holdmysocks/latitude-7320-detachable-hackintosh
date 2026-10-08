#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stdlib.h>
#include "tgl_xlate.h"
int main(int argc, char **argv)
{
   static uint8_t buf[1 << 20], out[1 << 20], ref[1 << 20];
   int bad = 0;
   for (int i = 1; i + 1 < argc; i += 2) {
      memset(buf, 0, sizeof(buf));
      FILE *f = fopen(argv[i], "rb"); fread(buf, 1, sizeof(buf), f); fclose(f);
      f = fopen(argv[i + 1], "rb"); int rl = (int)fread(ref, 1, sizeof(ref), f); fclose(f);
      struct tgl_xlate_info info;
      int n = tgl_xlate_kernel(buf, sizeof(buf), out, &info);
      int same = n == rl && !memcmp(out, ref, rl);
      printf("%s: %d bytes %s %s\n", argv[i], n, same ? "identical" : "DIFFERENT", info.reason ? info.reason : "");
      bad += !same;
   }
   /* arbitrary input must be rejected, not crash */
   srandom(7); unsigned long acc = 0;
   for (long it = 0; it < 300000; it++) { for (int k = 0; k < 512; k++) buf[k] = (uint8_t)random(); acc += tgl_xlate_kernel(buf, 512, out, NULL) > 0; }
   printf("random buffers accepted: %lu of 300000\n", acc);
   return bad;
}
