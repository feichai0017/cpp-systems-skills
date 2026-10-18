#include "operation.hpp"

#include <cassert>

int main() {
    project::SlotPool pool;
    assert(project::RunOperation(pool, true));
    assert(!project::RunOperation(pool, false));
    assert(project::RunOperation(pool, true));
    assert(pool.TryAcquire());
    assert(!project::RunOperation(pool, true));
    assert(!pool.TryAcquire());
    pool.Release();
    assert(project::RunOperation(pool, true));
}
