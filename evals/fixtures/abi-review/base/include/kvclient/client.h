#pragma once

#include <chrono>
#include <cstdint>
#include <string>
#include <string_view>

namespace kvclient {

enum class Consistency : std::uint8_t { kEventual = 0, kStrong = 1 };

// Implemented by callers to receive connection events.
class Observer {
public:
    virtual ~Observer() = default;
    virtual void OnConnected() = 0;
    virtual void OnError(int code) = 0;
};

inline std::chrono::milliseconds DefaultTimeout() { return std::chrono::milliseconds(500); }

class Client {
public:
    explicit Client(std::string endpoint);
    ~Client();
    Client(const Client&) = delete;
    Client& operator=(const Client&) = delete;

    // Returns 0 on success or an errno-style code.
    int Get(std::string_view key, std::string& value, Consistency consistency = Consistency::kEventual);
    int Put(std::string_view key, std::string_view value);
    void SetObserver(Observer* observer);

private:
    std::string endpoint_;
    Observer* observer_ = nullptr;
    int fd_ = -1;
};

}  // namespace kvclient
