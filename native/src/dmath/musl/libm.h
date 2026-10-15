// Stands in for musl's internal libm.h, which every vendored file here includes. The files are
// musl v1.1.19's src/math, unedited but for one marked line of tanh.c, compiled as C++ inside
// namespace dmath::musl by the wrappers one directory up (musl_*.cpp), so their sin, exp and the
// rest can never collide with, or be resolved to, the platform's C library. See ../dmath.h.
//
// Only what the vendored files use is defined: the IEEE word access macros, FORCE_EVAL,
// double_t, and the prototypes they call across files. sqrt and fabs come from the platform:
// IEEE requires both to be exact, so they agree everywhere.

#ifndef DMATH_MUSL_LIBM_H
#define DMATH_MUSL_LIBM_H

#include <cfloat>
#include <cmath>
#include <cstdint>
#include <cstring>

#include <math.h>

using std::fabs;
using std::isnan;
using std::sqrt;

// FLT_EVAL_METHOD is 0 on every target this builds for (SSE2 on x86_64, AArch64), so a
// double_t is a double; spelt out because <cmath> does not have to declare it globally.
typedef double dmath_double_t;
#define double_t dmath_double_t
typedef float dmath_float_t;
#define float_t dmath_float_t

// Raises the floating-point exceptions musl's code relies on, without its value being used.
#define FORCE_EVAL(x)                         \
	do {                                      \
		if (sizeof(x) == sizeof(float)) {     \
			volatile float __x;               \
			__x = (float)(x);                 \
			(void)__x;                        \
		} else {                              \
			volatile double __x;              \
			__x = (double)(x);                \
			(void)__x;                        \
		}                                     \
	} while (0)

// IEEE word access through memcpy, which every compiler turns into a register move and which,
// unlike musl's unions, is defined behaviour in C++.
#define EXTRACT_WORDS(hi, lo, d)              \
	do {                                      \
		uint64_t __i;                         \
		double __d = (d);                     \
		std::memcpy(&__i, &__d, 8);           \
		(hi) = (uint32_t)(__i >> 32);         \
		(lo) = (uint32_t)__i;                 \
	} while (0)

#define GET_HIGH_WORD(hi, d)                  \
	do {                                      \
		uint64_t __i;                         \
		double __d = (d);                     \
		std::memcpy(&__i, &__d, 8);           \
		(hi) = (uint32_t)(__i >> 32);         \
	} while (0)

#define GET_LOW_WORD(lo, d)                   \
	do {                                      \
		uint64_t __i;                         \
		double __d = (d);                     \
		std::memcpy(&__i, &__d, 8);           \
		(lo) = (uint32_t)__i;                 \
	} while (0)

#define INSERT_WORDS(d, hi, lo)                                     \
	do {                                                            \
		uint64_t __i = ((uint64_t)(hi) << 32) | (uint32_t)(lo);     \
		double __d;                                                 \
		std::memcpy(&__d, &__i, 8);                                 \
		(d) = __d;                                                  \
	} while (0)

#define SET_HIGH_WORD(d, hi)                                        \
	do {                                                            \
		uint64_t __i;                                               \
		double __d = (d);                                           \
		std::memcpy(&__i, &__d, 8);                                 \
		__i = (__i & 0xffffffffull) | ((uint64_t)(hi) << 32);       \
		std::memcpy(&__d, &__i, 8);                                 \
		(d) = __d;                                                  \
	} while (0)

#define SET_LOW_WORD(d, lo)                                         \
	do {                                                            \
		uint64_t __i;                                               \
		double __d = (d);                                           \
		std::memcpy(&__i, &__d, 8);                                 \
		__i = (__i & 0xffffffff00000000ull) | (uint32_t)(lo);       \
		std::memcpy(&__d, &__i, 8);                                 \
		(d) = __d;                                                  \
	} while (0)

namespace dmath::musl {

double exp(double);
double expm1(double);
double log(double);
double pow(double, double);
double sin(double);
double cos(double);
double tan(double);
double asin(double);
double acos(double);
double atan(double);
double atan2(double, double);
double tanh(double);
double scalbn(double, int);
double floor(double);

int __rem_pio2_large(double *, double *, int, int, int);
int __rem_pio2(double, double *);
double __sin(double, double, int);
double __cos(double, double);
double __tan(double, double, int);

} // namespace dmath::musl

#endif
