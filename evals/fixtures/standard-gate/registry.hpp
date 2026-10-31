#pragma once

#include <cstddef>
#include <map>
#include <string>
#include <utility>

namespace project {

struct Entry {
    std::string name;
    int priority = 0;
};

class Registry {
public:
    void Add(Entry entry) {
        const std::string key = entry.name;
        entries_[key] = std::move(entry);
    }

    std::size_t Size() const { return entries_.size(); }

private:
    std::map<std::string, Entry> entries_;
};

}  // namespace project
