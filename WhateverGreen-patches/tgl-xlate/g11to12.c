/* g11to12 - host front end of the Gen11 -> Gen12 EU translator (tgl_xlate.c), with Mesa's disassembler and validator. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "brw_eu.h"
#include "tgl_xlate.h"

static struct intel_device_info d11 = { .ver = 11, .verx10 = 110, .platform = INTEL_PLATFORM_ICL };
static struct intel_device_info d12 = { .ver = 12, .verx10 = 120, .platform = INTEL_PLATFORM_TGL };
static struct brw_isa_info isa11, isa12;

/* Length of a kernel: up to and including the first send with EOT, or to the first all-zero instruction slot. */
static int disassemble(const struct brw_isa_info *isa, const uint8_t *code, int size)
{
   const struct intel_device_info *devinfo = isa->devinfo;
   int o = 0;
   while (o + 8 <= size) {
      const brw_inst *in = (const brw_inst *)(code + o);
      brw_inst full;
      if (((const uint64_t *)in)[0] == 0) break;
      bool compacted = brw_inst_cmpt_control(devinfo, in);
      if (compacted) brw_uncompact_instruction(isa, &full, (brw_compact_inst *)in);
      else full = *in;
      printf("%04x %s ", o, compacted ? "c" : " ");
      brw_disassemble_inst(stdout, isa, &full, compacted, o, NULL);
      o += compacted ? 8 : 16;
      unsigned op = brw_inst_opcode(isa, &full);
      if ((op == BRW_OPCODE_SEND || op == BRW_OPCODE_SENDC || op == BRW_OPCODE_SENDS || op == BRW_OPCODE_SENDSC) && brw_inst_eot(devinfo, &full)) break;
   }
   return o;
}

int main(int argc, char **argv)
{
   brw_init_isa_info(&isa11, &d11);
   brw_init_isa_info(&isa12, &d12);
   if (argc < 3) { fprintf(stderr, "usage: g11to12 dis11|dis12|xlate file [out]\n"); return 2; }
   FILE *f = fopen(argv[2], "rb"); if (!f) { perror(argv[2]); return 1; }
   static uint8_t buf[1 << 20], out[1 << 20]; int n = (int)fread(buf, 1, sizeof(buf), f); fclose(f);
   if (!strcmp(argv[1], "dis11")) disassemble(&isa11, buf, n);
   else if (!strcmp(argv[1], "dis12")) disassemble(&isa12, buf, n);
   else if (!strcmp(argv[1], "xlate")) {
      struct tgl_xlate_info info;
      int len = tgl_xlate_kernel(buf, n, out, &info);
      int alen = len < 0 ? -len : len;
      printf("   %d instructions, %d bytes%s%s\n", info.instructions, alen, info.reason ? ", REJECTED: " : "", info.reason ? info.reason : "");
      if (info.reason) printf("   at offset 0x%x\n", info.offset);
      if (len > 0) {
         printf("-- Gen12 result:\n");
         int end = disassemble(&isa12, out, alen);
         printf("-- validation: %s\n", brw_validate_instructions(&isa12, out, 0, end, (struct disasm_info *)out) ? "passed" : "FAILED");
         if (argc > 3) { FILE *g = fopen(argv[3], "wb"); fwrite(out, 1, alen, g); fclose(g); }
      }
      return len > 0 ? 0 : 1;
   }
   return 0;
}
