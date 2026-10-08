/* tgl_xlate.h - Gen11 -> Gen12 EU code translator */
#ifndef TGL_XLATE_H
#define TGL_XLATE_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
struct tgl_xlate_info {
   const char *reason;   /* first reason a kernel was rejected, or NULL */
   int offset;           /* byte offset of the instruction it applies to */
   int instructions;
   int need_more;        /* rejected because the kernel continues past the bytes given: retry with more */
};
/* Translate the kernel at code (at most size bytes, ends at the first send with EOT) into out.
 * Returns its length in bytes, or a negative number if any instruction could not be translated: then out must
 * not be used. Not reentrant: the caller serialises. */
int tgl_xlate_kernel(const uint8_t *code, int size, uint8_t *out, struct tgl_xlate_info *info);
#ifdef __cplusplus
}
#endif
#endif
