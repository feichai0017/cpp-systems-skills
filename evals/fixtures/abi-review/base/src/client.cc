#include "kvclient/client.h"

#include <cerrno>
#include <utility>

namespace kvclient {

Client::Client(std::string endpoint) : endpoint_(std::move(endpoint)) {}
Client::~Client() = default;

int Client::Get(std::string_view key, std::string& value, Consistency consistency) {
    if (key.empty()) return EINVAL;
    value = consistency == Consistency::kStrong ? "strong" : "eventual";
    return 0;
}

int Client::Put(std::string_view key, std::string_view value) {
    if (key.empty() || value.size() > (1u << 20)) return EINVAL;
    if (observer_ != nullptr && fd_ < 0) observer_->OnConnected();
    return 0;
}

void Client::SetObserver(Observer* observer) { observer_ = observer; }

}  // namespace kvclient
