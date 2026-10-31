# CMake：目标、依赖与预设

修改或新建 CMake 项目时阅读。沿用项目已有的最低 CMake 版本、目录结构和依赖来源；下面的写法按“以目标为中心”的现代 CMake 组织，版本要求标在相应条目上。官方入口：[cmake-buildsystem](https://cmake.org/cmake/help/latest/manual/cmake-buildsystem.7.html)、[cmake-presets](https://cmake.org/cmake/help/latest/manual/cmake-presets.7.html)、[FetchContent](https://cmake.org/cmake/help/latest/module/FetchContent.html)。查阅时以项目所用 CMake 版本的文档为准。

## 原则

- 一切设置挂在目标上：`target_sources`、`target_include_directories`、`target_compile_features`、`target_compile_definitions`、`target_compile_options`、`target_link_libraries`，并写明 `PUBLIC`/`PRIVATE`/`INTERFACE`。
- `PUBLIC` 表示下游也需要（出现在公开头文件里的依赖、include 路径、编译特性）；`PRIVATE` 只用于本目标的实现；`INTERFACE` 用于纯头文件库或只传给下游的设置。
- 依赖通过导入目标链接，例如 `fmt::fmt`、`absl::flat_hash_map`、`GTest::gtest_main`，不写库文件路径或 `-lfoo`。
- 不用目录级的 `include_directories`、`link_directories`、`add_definitions`、`link_libraries`，不在 `CMakeLists.txt` 里修改 `CMAKE_CXX_FLAGS`。
- 源文件显式列出。`file(GLOB)` 不会在新增文件时自动重新配置；确需使用时加 `CONFIGURE_DEPENDS` 并接受其开销。
- 构建目录在源码树之外（或被 `.gitignore` 忽略），配置差异放进 presets，而不是要求每个人记住命令行参数。

## 库与可执行文件

```cmake
cmake_minimum_required(VERSION 3.24)
project(kvstore VERSION 0.1.0 LANGUAGES CXX)

include(GNUInstallDirs)                # 提供 CMAKE_INSTALL_INCLUDEDIR 等路径变量
set(CMAKE_CXX_EXTENSIONS OFF)          # 用 -std=c++20 而不是 -std=gnu++20

# 警告集中在一个接口目标里，由各目标按需链接。
add_library(kvstore_warnings INTERFACE)
target_compile_options(kvstore_warnings INTERFACE
  "$<$<CXX_COMPILER_ID:GNU,Clang,AppleClang>:-Wall;-Wextra;-Wpedantic;-Wshadow;-Wnon-virtual-dtor;-Wold-style-cast>"
  "$<$<CXX_COMPILER_ID:MSVC>:/W4;/permissive->")

add_library(kvstore_storage
  src/storage/segment.cc
  src/storage/segment_index.cc)
add_library(kvstore::storage ALIAS kvstore_storage)

target_include_directories(kvstore_storage
  PUBLIC
    "$<BUILD_INTERFACE:${PROJECT_SOURCE_DIR}/include>"
    "$<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>"
  PRIVATE
    "${PROJECT_SOURCE_DIR}/src")
target_compile_features(kvstore_storage PUBLIC cxx_std_20)
target_link_libraries(kvstore_storage
  PUBLIC  fmt::fmt                                   # 公开头文件用到了 fmt
  PRIVATE absl::flat_hash_map
          "$<BUILD_INTERFACE:kvstore_warnings>")     # 不进入导出集

add_executable(kvstore_server src/server/main.cc)
target_link_libraries(kvstore_server PRIVATE kvstore::storage "$<BUILD_INTERFACE:kvstore_warnings>")
```

- 用 `target_compile_features(... cxx_std_20)` 声明目标需要的最低标准，它会随 `PUBLIC` 传给下游。顶层项目要统一标准时再设置 `CMAKE_CXX_STANDARD`，作为库被别人使用时不要强行覆盖。
- 静态库的 `PRIVATE` 依赖仍会出现在导出的链接接口中；只在构建期使用的接口目标（如警告集合）用 `$<BUILD_INTERFACE:...>` 包住，否则安装导出时会报“目标不在导出集中”。
- `-Werror` 不写死在 `CMakeLists.txt` 里，而是在 CI 或 preset 中设置 `CMAKE_COMPILE_WARNING_AS_ERROR=ON`（CMake 3.24+），避免下游因为新编译器的新警告而无法构建。
- `ALIAS` 目标让项目内和安装后的使用方式一致（都写 `kvstore::storage`），拼错名字时在配置阶段报错，而不是变成链接 `-lkvstore::storage`。

## 依赖管理

在一个项目里选定一种主要来源，并把版本固定下来。

| 方式 | 适用场景 | 要点 |
| --- | --- | --- |
| `find_package(Foo CONFIG REQUIRED)` | 依赖由系统、容器镜像或包管理器提供 | 优先 CONFIG 模式和导入目标；最低版本写在 `find_package(Foo 1.2 ...)` |
| vcpkg 清单模式 | 跨平台、依赖多、希望和 CMake 无缝集成 | `vcpkg.json` + `builtin-baseline` 固定 ports；通过 toolchain 文件接入 |
| Conan 2 | 需要二进制缓存、多配置矩阵或已有 Conan 体系 | `CMakeDeps` + `CMakeToolchain` 生成器，使用生成的 presets |
| FetchContent | 少量依赖、希望一条 `cmake` 命令完成构建 | 固定到 tag 或提交，下载包加 `URL_HASH`；3.24+ 用 `FIND_PACKAGE_ARGS` 优先复用已安装版本 |
| git submodule + `add_subdirectory` | 需要随源码修改依赖，或离线构建 | 固定提交；依赖自己的选项要在 `add_subdirectory` 之前设置 |
| vendor 到 `third_party/` | 很小、很少更新的库 | 记录来源、版本、许可证和本地修改 |

FetchContent 示例（3.24+）：

```cmake
include(FetchContent)
FetchContent_Declare(googletest
  URL https://github.com/google/googletest/archive/refs/tags/v1.15.2.tar.gz
  URL_HASH SHA256=<下载文件的 sha256>
  FIND_PACKAGE_ARGS NAMES GTest)
FetchContent_MakeAvailable(googletest)
```

vcpkg 清单模式：

```json
{
  "name": "kvstore",
  "version": "0.1.0",
  "dependencies": ["fmt", "abseil", "gtest"],
  "builtin-baseline": "<vcpkg 仓库的提交 sha>"
}
```

配置时传入 `-DCMAKE_TOOLCHAIN_FILE=$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake`，或写进 preset 的 `toolchainFile`。

Conan 2：

```text
# conanfile.txt
[requires]
fmt/11.0.2
[generators]
CMakeDeps
CMakeToolchain
[layout]
cmake_layout
```

```sh
conan install . --build=missing -s build_type=Release
cmake --preset conan-release
cmake --build --preset conan-release
```

依赖一致性：同一进程里同一个库只能有一个版本。所有依赖使用一致的标准库 ABI（例如 libstdc++ 的 `_GLIBCXX_USE_CXX11_ABI`）、异常/RTTI 设置、sanitizer 设置，以及会影响头文件布局的选项（Abseil 的 C++ 标准选项、Boost 的配置宏）。预编译二进制和源码构建混用时尤其要核对。

## 测试

```cmake
include(CTest)                          # 提供 BUILD_TESTING 选项并启用 ctest
if(BUILD_TESTING)
  add_executable(segment_test tests/storage/segment_test.cc)
  target_link_libraries(segment_test PRIVATE kvstore::storage GTest::gtest_main)
  include(GoogleTest)
  gtest_discover_tests(segment_test)
endif()
```

作为子项目被别人 `add_subdirectory` 时，可以用 `PROJECT_IS_TOP_LEVEL`（3.21+）决定是否构建测试、示例和 benchmark。

## Presets

`CMakePresets.json` 提交到仓库，个人设置放在不提交的 `CMakeUserPresets.json`：

```json
{
  "version": 6,
  "configurePresets": [
    {
      "name": "debug",
      "generator": "Ninja",
      "binaryDir": "${sourceDir}/build/${presetName}",
      "cacheVariables": {
        "CMAKE_BUILD_TYPE": "Debug",
        "CMAKE_EXPORT_COMPILE_COMMANDS": "ON"
      }
    },
    {
      "name": "release",
      "inherits": "debug",
      "cacheVariables": { "CMAKE_BUILD_TYPE": "RelWithDebInfo" }
    },
    {
      "name": "asan",
      "inherits": "debug",
      "cacheVariables": {
        "CMAKE_CXX_FLAGS": "-fsanitize=address,undefined -fno-omit-frame-pointer",
        "CMAKE_EXE_LINKER_FLAGS": "-fsanitize=address,undefined",
        "CMAKE_SHARED_LINKER_FLAGS": "-fsanitize=address,undefined"
      }
    },
    {
      "name": "ci",
      "inherits": "release",
      "cacheVariables": { "CMAKE_COMPILE_WARNING_AS_ERROR": "ON" }
    }
  ],
  "buildPresets": [
    { "name": "debug", "configurePreset": "debug" },
    { "name": "asan", "configurePreset": "asan" }
  ],
  "testPresets": [
    { "name": "debug", "configurePreset": "debug", "output": { "outputOnFailure": true } },
    { "name": "asan", "configurePreset": "asan", "output": { "outputOnFailure": true } }
  ]
}
```

```sh
cmake --preset debug
cmake --build --preset debug
ctest --preset debug
```

presets 版本 6 需要 CMake 3.25+；项目最低版本更低时降低 `version` 并去掉对应字段。TSan 单独建一个 preset，不和 ASan 放在一起。

## 编译缓存与编译数据库

- `CMAKE_EXPORT_COMPILE_COMMANDS=ON` 生成 `compile_commands.json`，供 clangd 和 clang-tidy 使用（Ninja 和 Makefile 生成器支持）。
- 编译缓存用 `CMAKE_CXX_COMPILER_LAUNCHER=ccache`（或 sccache），放在 preset 或环境里，不写死在 `CMakeLists.txt`。

## 共享库与安装

- 共享库默认隐藏符号：`set_target_properties(lib PROPERTIES CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN ON)`，用 `GenerateExportHeader` 生成导出宏标注公开 API。
- 对外分发的库提供安装和包配置，让下游可以 `find_package`：

```cmake
include(CMakePackageConfigHelpers)
install(TARGETS kvstore_storage EXPORT kvstoreTargets)
install(DIRECTORY include/ DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}")
install(EXPORT kvstoreTargets
  NAMESPACE kvstore::
  DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/kvstore")
```

  再用 `configure_package_config_file` 和 `write_basic_package_version_file` 生成 `kvstoreConfig.cmake` 与版本文件。CMake 3.23+ 也可以用 `target_sources(... FILE_SET HEADERS ...)` 同时声明并安装公开头文件。
- 内部服务不对外分发时，不必为安装和导出编写配置。

## CUDA

```cmake
project(kvstore LANGUAGES CXX CUDA)
find_package(CUDAToolkit REQUIRED)

add_library(kvstore_kernels src/kernels/copy.cu)
set_target_properties(kvstore_kernels PROPERTIES CUDA_ARCHITECTURES "80;90")
target_compile_features(kvstore_kernels PUBLIC cuda_std_17)
target_link_libraries(kvstore_kernels PUBLIC CUDA::cudart)
```

`CUDA_ARCHITECTURES` 按实际部署的 GPU 填写；只在需要跨编译单元调用设备函数时才打开 `CUDA_SEPARABLE_COMPILATION`。

## 常见错误

| 写法 | 问题 | 改为 |
| --- | --- | --- |
| `include_directories(${CMAKE_SOURCE_DIR}/include)` | 所有目标共享 include 路径，隐藏真实依赖 | `target_include_directories` |
| `target_link_libraries(app foo)` 不写关键字 | 混用两种签名，传递性含混 | 写明 `PUBLIC`/`PRIVATE` |
| `set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++20 -O2")` | 覆盖用户和 preset 的设置 | `target_compile_features` + `CMAKE_BUILD_TYPE` |
| `target_link_libraries(app /usr/lib/libfoo.a)` | 不可移植，丢失依赖的 include 和传递依赖 | `find_package` 后链接导入目标 |
| 在库里 `set(CMAKE_CXX_STANDARD 17)` | 被别的项目 `add_subdirectory` 时改变整个构建 | 目标级 `cxx_std_17` |
| `FetchContent` 不固定版本 | 构建不可复现 | 固定 tag/提交和 `URL_HASH` |
| 在 `CMakeLists.txt` 里加 `-Werror` | 下游换编译器后无法构建 | CI preset 中设置 `CMAKE_COMPILE_WARNING_AS_ERROR` |
