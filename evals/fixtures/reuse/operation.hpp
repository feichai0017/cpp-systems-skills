#pragma once

namespace project {

class SlotPool {
public:
    bool TryAcquire() {
        if (occupied_) return false;
        occupied_ = true;
        return true;
    }
    void Release() { occupied_ = false; }

private:
    bool occupied_ = false;
};

bool RunOperation(SlotPool& pool, bool succeeds);

}  // namespace project
