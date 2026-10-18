#include "window.hpp"

#include <cassert>

int main() {
    project::Store store;
    assert(!store.Read());
    store.Replace("previous");
    const auto previous = store.Read();
    assert(previous);
    const auto view = previous->View();
    store.Replace("current");
    assert(view == "previous");
    assert(store.Read()->View() == "current");
    store.Replace("");
    const auto empty = store.Read();
    assert(empty && empty->View().empty());
}
