/*
 * kruntime.c - what Mesa's EU encoder needs from a C library, for the kernel build.
 *
 * Memory comes from one static arena that is reset at the start of every translation (ralloc_context), so
 * nothing is allocated or freed at run time. The caller serialises translations.
 */
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include "brw_eu.h"

extern volatile int kshim_assert_failed;
uint64_t intel_debug = 0;

static uint8_t arena[5 * 1024 * 1024] __attribute__((aligned(16)));
static size_t arena_used;

static void *bump(size_t size)
{
   size = (size + 15) & ~(size_t)15;
   if (size > sizeof(arena) || arena_used + size > sizeof(arena)) {
      /* Never expected (a kernel is capped at 1000 instructions). Hand back the start of the arena so the
       * caller writes into owned memory, and fail the translation. */
      kshim_assert_failed = 1;
      return arena;
   }
   void *p = arena + arena_used;
   arena_used += size;
   memset(p, 0, size);
   return p;
}

void *ralloc_context(const void *ctx) { (void)ctx; arena_used = 0; return bump(16); }
void ralloc_free(void *p) { (void)p; }
void *ralloc_size(const void *ctx, size_t size) { (void)ctx; return bump(size); }
void *rzalloc_array_size(const void *ctx, size_t size, unsigned count) { (void)ctx; return bump(size * count); }
void *reralloc_array_size(const void *ctx, void *ptr, size_t size, unsigned count)
{
   /* Mesa grows its arrays by doubling, and the old block's size is not recorded here: take a new block and
    * copy half of the new size from the old one (both lie inside the arena) */
   (void)ctx;
   void *p = bump(size * count);
   if (ptr && p != (void *)arena && !kshim_assert_failed) memcpy(p, ptr, size * count / 2);
   return p;
}
void *reralloc_size(const void *ctx, void *ptr, size_t size) { (void)ctx; (void)size; kshim_assert_failed = 1; return ptr; }
void *calloc(size_t count, size_t size) { return bump(count * size); }
void *kshim_malloc(size_t size) { return bump(size); }
void kshim_free(void *p) { (void)p; }
void kshim_abort(void) { kshim_assert_failed = 1; }

/* Referenced by code paths the translator never takes */
int brw_disassemble_inst(FILE *file, const struct brw_isa_info *isa, const brw_inst *inst, bool is_compacted, int offset, const struct brw_label *root_label)
{
   (void)file; (void)isa; (void)inst; (void)is_compacted; (void)offset; (void)root_label;
   return 0;
}

void *kshim_memmove(void *dst, const void *src, size_t n)
{
   uint8_t *d = dst; const uint8_t *s = src;
   if (d < s) while (n--) *d++ = *s++;
   else { d += n; s += n; while (n--) *--d = *--s; }
   return dst;
}

/* From Mesa's brw_disasm.c (not built into the kernel): which flow-control opcodes carry JIP / UIP on Gen6+ */
bool
brw_has_jip(const struct intel_device_info *devinfo, enum opcode opcode)
{
   if (devinfo->ver < 6)
      return false;

   return opcode == BRW_OPCODE_IF ||
          opcode == BRW_OPCODE_ELSE ||
          opcode == BRW_OPCODE_ENDIF ||
          opcode == BRW_OPCODE_WHILE ||
          opcode == BRW_OPCODE_BREAK ||
          opcode == BRW_OPCODE_CONTINUE ||
          opcode == BRW_OPCODE_HALT;
}

bool
brw_has_uip(const struct intel_device_info *devinfo, enum opcode opcode)
{
   if (devinfo->ver < 6)
      return false;

   return (devinfo->ver >= 7 && opcode == BRW_OPCODE_IF) ||
          (devinfo->ver >= 8 && opcode == BRW_OPCODE_ELSE) ||
          opcode == BRW_OPCODE_BREAK ||
          opcode == BRW_OPCODE_CONTINUE ||
          opcode == BRW_OPCODE_HALT;
}

