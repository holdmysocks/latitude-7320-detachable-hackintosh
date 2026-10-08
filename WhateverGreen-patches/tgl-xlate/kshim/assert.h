/* kernel shim: assert.h. A failed assertion in the encoder marks the translation as failed instead of panicking. */
#undef assert
extern volatile int kshim_assert_failed;
#define assert(x) ((void)((x) || (kshim_assert_failed = 1)))
#ifndef static_assert
#define static_assert _Static_assert
#endif
