#include "config_store.hpp"
#include "posix_fs.hpp"

#include <cassert>
#include <filesystem>
#include <string>

int main() {
    const auto dir = std::filesystem::temp_directory_path() / "durable_config_check";
    std::filesystem::remove_all(dir);
    std::filesystem::create_directories(dir);
    const std::string path = (dir / "service.conf").string();

    project::fs::PosixFileSystem fs;
    assert(!project::SaveConfig(fs, path, "mode=fast\n"));
    std::string text;
    assert(!project::LoadConfig(fs, path, text) && text == "mode=fast\n");

    assert(!project::SaveConfig(fs, path, "mode=safe\nretries=3\n"));
    assert(!project::LoadConfig(fs, path, text) && text == "mode=safe\nretries=3\n");

    std::filesystem::remove_all(dir);
}
