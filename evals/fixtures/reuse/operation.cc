#include "operation.hpp"

namespace project {

bool RunOperation(SlotPool& pool, bool succeeds) {
    if (!pool.TryAcquire()) return false;
    if (!succeeds) return false;
    pool.Release();
    return true;
}

}  // namespace project
