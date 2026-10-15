// musl/floor.c compiled into namespace dmath::musl; one file per translation unit, as the vendored
// files share static constant names (huge, tiny, ...). See musl/libm.h.
#include "musl/libm.h"

namespace dmath::musl {
#include "musl/floor.c"
} // namespace dmath::musl
