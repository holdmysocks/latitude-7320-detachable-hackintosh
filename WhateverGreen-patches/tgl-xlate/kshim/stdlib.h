/* kernel shim: stdlib.h */
#ifndef KSHIM_STDLIB_H
#define KSHIM_STDLIB_H
#include <stddef.h>
void *kshim_malloc(size_t size);
void kshim_free(void *p);
void kshim_abort(void);
#define malloc kshim_malloc
#define free kshim_free
#define abort kshim_abort
#define getenv(x) ((char *)0)
#endif
