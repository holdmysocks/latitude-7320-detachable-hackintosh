/* kernel shim: stdio.h. The EU encoder only prints in debug paths; in the kernel those print nothing. */
#ifndef KSHIM_STDIO_H
#define KSHIM_STDIO_H
#include <stddef.h>
#include <stdarg.h>
typedef struct kshim_file FILE;
#define stderr ((FILE *)0)
#define stdout ((FILE *)0)
static inline int kshim_noprint(FILE *f, const char *fmt, ...) { (void)f; (void)fmt; return 0; }
#define fprintf kshim_noprint
#define fputs(s, f) 0
#define fputc(c, f) 0
#define fwrite(p, s, n, f) 0
#define fflush(f) 0
int snprintf(char *, size_t, const char *, ...);
#endif
