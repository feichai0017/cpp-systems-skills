#pragma once

#include <map>
#include <string>

namespace project {

struct Config {
    std::string value;
};

class ConfigStore {
public:
    void Set(const std::string& name, Config config) { configs_[name] = std::move(config); }

    const Config* FindConfig(const std::string& name) const {
        const auto it = configs_.find(name);
        return it == configs_.end() ? nullptr : &it->second;
    }

private:
    std::map<std::string, Config> configs_;
};

}  // namespace project
