/* Minimal replacements for the parts of Mesa the stand-alone EU tool does not build. */
#include <stdlib.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <stdint.h>
#include "brw_eu.h"
uint64_t intel_debug = 0;
void *ralloc_context(const void *ctx) { return calloc(1, 16); }
void ralloc_free(void *p) { }
void *ralloc_size(const void *ctx, size_t size) { return calloc(1, size); }
void *rzalloc_array_size(const void *ctx, size_t size, unsigned count) { return calloc(count, size); }
void *reralloc_size(const void *ctx, void *ptr, size_t size) { return realloc(ptr, size); }
char *ralloc_asprintf(const void *ctx, const char *fmt, ...) { char *s = NULL; va_list a; va_start(a, fmt); vasprintf(&s, fmt, a); va_end(a); return s; }
float brw_vf_to_float(unsigned char vf) { return 0.0f; }
void disasm_insert_error(struct disasm_info *disasm, unsigned offset, unsigned inst_size, const char *error) { printf("      VALIDATION @%u: %s", offset, error); }
void *reralloc_array_size(const void *ctx, void *ptr, size_t size, unsigned count) { return realloc(ptr, size * count); }
