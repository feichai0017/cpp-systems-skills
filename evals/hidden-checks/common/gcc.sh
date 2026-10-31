# Sourced by hidden checks. Sets GXX to a real GCC (libstdc++) or leaves it empty.
# libc++ offers C++11 library types such as std::unique_ptr even under -std=c++98,
# so C++98 conformance of library usage is only checked with libstdc++.
if [ -z "${GXX:-}" ]; then
  for candidate in g++-15 g++-14 g++-13 g++; do
    if command -v "$candidate" >/dev/null && "$candidate" --version 2>/dev/null | grep -q "Free Software Foundation"; then
      GXX="$(command -v "$candidate")"; break
    fi
  done
fi
GXX="${GXX:-}"
