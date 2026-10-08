#include <execinfo.h>
#include <signal.h>
#include <unistd.h>
static void h(int s){ void *b[32]; int n=backtrace(b,32); backtrace_symbols_fd(b,n,2); _exit(1);}
__attribute__((constructor)) static void i(void){ signal(SIGABRT,h); }
