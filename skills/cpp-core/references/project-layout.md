# 项目结构与文件摆放

新增文件、拆分模块或建立新项目时阅读。已有项目沿用它现有的目录结构、后缀（`.h`/`.hpp`、`.cc`/`.cpp`）、include 路径写法和测试位置；下面是没有既有约定时的默认做法。

## 两种常见布局

**独立库或服务（CMake）**：公开头文件与实现分开，便于安装和控制对外接口。

```text
kvstore/
├── CMakeLists.txt
├── CMakePresets.json
├── cmake/                     # 项目自己的 CMake 模块：警告、sanitizer、安装配置
├── include/kvstore/           # 公开头文件，安装后对外可见
│   └── storage/segment.h
├── src/                       # 实现文件和私有头文件
│   └── storage/
│       ├── segment.cc
│       └── segment_index.h    # 私有头文件，不安装
├── tests/storage/segment_test.cc
├── benchmarks/
├── examples/
└── third_party/               # 仅在确需 vendor 时使用，附版本、来源和许可证
```

**单仓库多模块（Blade、Bazel 风格）**：每个目录一个 `BUILD`，头文件、实现和测试放在同一目录，include 路径从工作区根目录写起。

```text
workspace/
├── BLADE_ROOT
├── common/base/
│   ├── BUILD
│   ├── status.h
│   └── status.cc
└── storage/segment/
    ├── BUILD
    ├── segment.h
    ├── segment.cc
    └── segment_test.cc
```

```cpp
#include "storage/segment/segment.h"   // 从工作区根目录写全路径
```

## 文件划分

- 一个主要类型或一组紧密相关的函数对应一对头文件和实现文件，文件名与主要类型一致（按项目的大小写风格，例如 `segment_index.h` 对应 `SegmentIndex`）。
- 公开头文件只放调用方需要的声明。只在一个实现文件里使用的类型和函数放在该文件的匿名命名空间里；多个实现文件共享但不对外的放私有头文件或 `internal/` 目录。
- 模板和 `inline` 函数的定义放在头文件。实现很长时可以放在 `segment-inl.h` 一类的文件中，由主头文件在末尾 include。
- 生成的代码（protobuf、flatbuffers）放在构建目录，按生成规则规定的全路径 include，不提交到源码树，除非项目明确这样做。
- 测试与被测代码同目录（单仓库风格）或在 `tests/` 下镜像 `src/` 结构（独立库风格），二选一并保持一致。测试专用的辅助代码放在测试目录，不放进产品库。

## 头文件规则

- **自包含**：任何头文件单独 include 都能编译。实现文件第一个 include 自己的头文件，可以持续检查这一点。
- **include 顺序**：自己的头文件 → C 系统头文件 → C++ 标准库 → 第三方库 → 本项目其他头文件，每组之间空一行。项目的 clang-format 有 `IncludeCategories` 配置时以配置为准。
- **include 什么就用什么**：用到哪个符号就 include 声明它的头文件，不依赖间接包含。可以用 include-what-you-use 或 clang-tidy 的 `misc-include-cleaner` 检查。
- **保护**：沿用项目现有的 `#pragma once` 或 include guard；include guard 按路径命名，例如 `KVSTORE_STORAGE_SEGMENT_H_`。
- **前置声明**：用来切断头文件之间的编译依赖，前提是头文件只用到指针或引用。不前置声明标准库类型和其他项目的类型；被前置声明的类型若需要完整定义才能正确析构，用 Pimpl 并在实现文件中定义析构函数。
- 头文件里不写 `using namespace`，不定义非 `inline` 的变量或函数，不放有构造开销的全局对象。

## 模块分层

- 依赖只从上层指向下层，例如 `base` → `util` → `storage` → `service` → `app`，同层之间按职责划分，禁止循环依赖。
- 一个库的公开头文件里用到的依赖是它的公开依赖；只在实现文件里用到的是私有依赖。在构建系统里如实区分（CMake 的 `PUBLIC`/`PRIVATE`，Blade 的 `hdrs`/`srcs` 与 `deps`）。
- 库的粒度按职责和依赖划分：一个库只因为一个原因而变化。把很少用到的重依赖（gtest 的 `gtest_prod.h`、CUDA、平台相关代码）拆成独立的小库，避免下游被迫链接。
- 平台相关实现放在单独文件（`file_linux.cc`、`file_darwin.cc`），由构建系统选择编译哪个，而不是在一个文件里写满 `#ifdef`。

## CUDA 与混合代码

- 设备代码放 `.cu`/`.cuh`，主机端公开头文件不 include CUDA 头文件；需要在接口里暴露 stream 或设备指针时，用不透明句柄或项目的封装类型。
- kernel 和对应的 host 启动函数放在同一个 `.cu` 文件，对外只暴露 host 函数的声明。

## 新增文件时的检查

1. 文件放在正确的层和目录，名称与主要类型一致。
2. 加入构建目标：CMake 的 `target_sources`/`add_library`，Blade 的 `srcs`/`hdrs`；公开头文件出现在对应位置。
3. 依赖按公开/私有声明；不靠全局 include 路径或间接依赖碰巧通过编译。
4. 测试加入测试目标并能被项目的测试命令发现。
