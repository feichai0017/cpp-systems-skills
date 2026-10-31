#include "config_store.hpp"
#include "registry.hpp"

#include <cassert>

int main() {
    project::Registry registry;
    registry.Add({"reader", 2});
    registry.Add({"writer", 5});
    assert(registry.Size() == 2);

    project::ConfigStore store;
    store.Set("mode", {"fast"});
    assert(store.FindConfig("mode") != nullptr);
    assert(store.FindConfig("missing") == nullptr);
}
