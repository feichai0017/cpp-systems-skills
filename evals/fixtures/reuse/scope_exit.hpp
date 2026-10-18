#pragma once

#include <utility>

namespace project {

template <typename Cleanup>
class ScopeExit {
public:
    explicit ScopeExit(Cleanup cleanup) : cleanup_(std::move(cleanup)) {}
    ScopeExit(const ScopeExit&) = delete;
    ScopeExit& operator=(const ScopeExit&) = delete;
    ScopeExit(ScopeExit&&) = delete;
    ScopeExit& operator=(ScopeExit&&) = delete;
    ~ScopeExit() noexcept { cleanup_(); }

private:
    Cleanup cleanup_;
};

}  // namespace project
