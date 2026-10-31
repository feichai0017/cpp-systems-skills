# 参考来源与改写边界

整理日期：2026-10-18。C++ 工程规范以 DuckDB 官方贡献指南和相关实现为主要参考，其他社区技能提供组织与审查方向。下面记录来源和适配理由，不将任何项目约定当作 C++ 语言标准。

## 主要工程参考：DuckDB

[DuckDB 工程参考](../skills/cpp-core/references/duckdb.md) 记录固定提交 `1b4c3e54ba3625bac56ad184f0ce642a8d2bfbd5` 的贡献指南、受检查的容器包装、`BufferHandle` 与 vector 表示接口，以及本合集的迁移判断。

已阅读列出的源码；没有构建整个 DuckDB，也没有使用其项目成熟度或 benchmark 为本项目证明性能。错误策略、基础类型、格式化与测试框架保持项目自身约定。

## 技能组织参考

| 来源 | 采用的方向 | 本合集的适配 |
| --- | --- | --- |
| [ECC cpp-coding-standards](https://github.com/affaan-m/ECC/blob/main/skills/cpp-coding-standards/SKILL.md) | 资源安全、值语义、类型与接口合同 | 项目错误策略、命名、文件后缀和语言标准优先；不搬入整套风格 |
| [DeevsDeevs anti-ai-slop](https://github.com/DeevsDeevs/agent-system/blob/HEAD/anti-ai-slop/SKILL.md) | 审视冗余检查、异常层与包装，保留信任边界校验 | 删除前证明保证；评审范围显式选择，保留所有相关 diff 层 |
| [karpathy-guidelines](https://github.com/multica-ai/andrej-karpathy-skills/blob/main/skills/karpathy-guidelines/SKILL.md) | 控制任务范围，以可验证结果驱动实现 | 不按调用次数否定抽象；一次性 RAII 仍可能有实际职责 |
| [Jeffallan cpp-pro](https://github.com/Jeffallan/claude-skills/blob/main/skills/cpp-pro/SKILL.md) | 按需查询现代 C++、并发与工具 | 特性与工具服从任务和项目，不预设 concepts 或统一新构建配置 |

ECC 与 karpathy-guidelines 的原始用户链接分别重定向到上表地址。四个技能的正文均已读取；Jeffallan 的 build-tooling 参考也已核对，没有宣称读取所有下级参考文件。

本合集没有复制上游全文或 C++ 示例，规则、案例和辅助脚本重新编写。后续如引入上游代码或文档片段，应检查对应版本的许可与署名要求；本仓库的许可不替代上游许可。

## 项目参考与基础库

[复用与源码参考](../skills/cpp-core/references/reuse-and-precedents.md) 保留本地查找、外部源码核对和 Rust 机制迁移的方法，分别按用途进入以下两个包内索引：

- [项目与实现参考](../skills/cpp-core/references/project-references.md)：DuckDB 为主，LLVM 补充语义命名、库分层与借用接口；LevelDB、RocksDB、Arrow、Seastar 按存储、内存和并发机制选择。Tokio semaphore、Crossbeam epoch 继续作为所有权机制的补充。
- [基础库选型](../skills/cpp-core/references/library-selection.md)：fmt、spdlog、Abseil、Boost.Asio、Boost.Interprocess、Folly、GoogleTest 与 Google Benchmark 的官方入口，以及地址稳定性、ABI、运行时和资源回收的适配条件。
- [共享内存与状态服务先例](../skills/cpp-core/references/shared-memory-state-precedents.md)：固定提交的 Vineyard daemon/IPC/mmap 与 Blob 生命周期、Ray Plasma 对象生命周期和 wire descriptor、LMDB 读快照/reader table、iceoryx loan/take/release 与崩溃 cleanup，以及 iceoryx2 的所有权和阶段命名。

新增条目依据官方规范、使用文档与相关接口；推荐用途是本合集的工程判断，没有对所有候选做完整源码审计、构建或性能比较。此前核对过的 Folly ScopeGuard、Boost offset_ptr、Seastar sharded、Tokio semaphore 和 Crossbeam Guard 的具体入口保留在对应索引中。

除 DuckDB 的固定源码快照外，这些入口多指向移动分支或最新文档。实际采用时记录本次读取的 commit/tag、文件/符号与本地差异。没有复制这些项目的代码，也不以其成熟度或上游 benchmark 作为本项目的正确性或性能证据。

共享内存先例另行固定并阅读了 Vineyard `0cbaada9db11d0268aa166b91cb7503bab0ccf86`、Ray `6f01d617120885918b783086eedf712ebdb5f441`、LMDB `253ba5219172531b719bc14fee6b4aa1a2a5c4a5`、iceoryx `9f9fb0d359f1805cdd38006c8aba6af6dbc2209e` 和 iceoryx2 `9f1ddda76a51bf836c6cffe9cefe0006d0e74fae` 的相关文件。它们用于缩小职责、状态和命名判断，不表示建议新增这些依赖；未复制上游代码。

## Codex 自动选择

- [官方技能说明](https://learn.chatgpt.com/docs/build-skills)：按 description 选用技能、隐式调用策略和配置范围。
- [全局与项目 AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md)：个人默认约定、项目覆盖与启动时加载。

本合集用显式允许隐式调用的元数据配合简短的全局指令示例；没有实现或宣称存在固定的技能路由算法。

## 技术文档入口

- [C++ Core Guidelines](https://isocpp.github.io/CppCoreGuidelines/CppCoreGuidelines)：资源、接口、并发与错误处理的进一步参考；实际项目可有领域约束。
- [Clang AddressSanitizer](https://clang.llvm.org/docs/AddressSanitizer.html)
- [Clang ThreadSanitizer](https://clang.llvm.org/docs/ThreadSanitizer.html)
- [clang-tidy](https://clang.llvm.org/extra/clang-tidy/index.html)

工具行为需要与项目安装版本匹配。链接用于查证具体问题，不要求每次技能执行都访问或加载全部文档。

## 现代写法、结构与构建（2026-10-31）

- 现代写法：[C++ Core Guidelines](https://isocpp.github.io/CppCoreGuidelines/CppCoreGuidelines)、[Google C++ Style Guide](https://google.github.io/styleguide/cppguide.html)（核对时要求 C++20）、[Chromium C++ 特性规定](https://chromium.googlesource.com/chromium/src/+/main/styleguide/c++/c++-features.md)、[Abseil Tips of the Week](https://abseil.io/tips/)、[cppreference 编译器支持表](https://en.cppreference.com/w/cpp/compiler_support)。规则由本合集重新编写，示例为原创代码。
- DuckDB 写法规则：固定快照 `1b4c3e54ba3625bac56ad184f0ce642a8d2bfbd5` 的 CONTRIBUTING “C++ Guidelines” 一节；该快照的 `CMakeLists.txt` 要求 C++17 或更高。
- 代码库语言标准：读取各项目默认分支的顶层构建文件，Abseil 与 LevelDB 为 C++17，LLVM 要求 C++17，RocksDB 默认 C++20，Folly、Arrow、Velox、Mooncake（`mooncake-common/common.cmake`）、3FS 为 C++20，Seastar 要求 C++20 起，ClickHouse 为 C++23。这些是移动分支上的观察，使用时重新核对。
- CMake：[cmake-buildsystem](https://cmake.org/cmake/help/latest/manual/cmake-buildsystem.7.html)、[cmake-presets](https://cmake.org/cmake/help/latest/manual/cmake-presets.7.html)、[FetchContent](https://cmake.org/cmake/help/latest/module/FetchContent.html)、[vcpkg 清单模式](https://learn.microsoft.com/vcpkg/concepts/manifest-mode)、[Conan 2 CMake 集成](https://docs.conan.io/2/integrations/cmake.html)。参考中的示例项目（以导入目标替身代替 fmt/Abseil）在 Docker `gcc:14` 镜像中用 CMake 3.31 完成 presets 配置、构建、ctest、`CMAKE_COMPILE_WARNING_AS_ERROR` 构建与安装导出，并确认警告接口目标未进入导出集。
- Blade：[chen3feng/blade-build](https://github.com/chen3feng/blade-build) 固定提交 `b95bff3e4e35c3b53265c7522e42e1aedf84f3f8` 的 `doc/en` 下 C/C++ 规则、BUILD 文件、配置、命令行、测试、工作区、vcpkg、IDL 与编辑器支持文档。没有在 Blade 工作区中实际构建示例。
- clang-tidy：`examples/clang-tidy.modern.yaml` 中的检查名与可选检查用 clang-tidy 22.1.7 的 `--list-checks` 核对过。
- 标准库差异：`std::atomic<std::shared_ptr<T>>` 在 GCC 14 的 libstdc++ 中可用，在 LLVM 22 的 libc++ 中触发 “requires trivially copyable” 静态断言；GCC 14 在 `-std=c++14 -pedantic -Werror` 下接受 `[[nodiscard]]`，clang 22 拒绝。

## 系统编程专题（2026-10-31）

- 系统接口语义以 Linux man-pages 为准：`close(2)`（失败后不重试）、`write(2)`/`pread(2)`（部分完成与 `EINTR`）、`fsync(2)`、`rename(2)`、`open(2)`（`O_CLOEXEC`、`O_DIRECT` 对齐、`O_TMPFILE`）、`statx(2)`（`STATX_DIOALIGN`）、`signal-safety(7)`、`pidfd_open(2)`、`fcntl(2)`（OFD 锁）。
- `fsync` 失败后的语义参考 PostgreSQL 社区 2018 年对 Linux 回写错误处理的讨论（常称 fsyncgate）：错误可能只报告一次，之后的 `fsync` 成功不代表数据已落盘。
- 编译加固选项参考 [OpenSSF 编译器加固指南](https://best.openssf.org/Compiler-Hardening-Guides/Compiler-Options-Hardening-Guide-for-C-and-C++.html)。
- 无锁回收与异步：C++26 工作草案中的 `std::hazard_pointer`、`std::rcu` 与 `std::execution`；Folly `hazptr`、liburcu、`folly::coro` 与 Asio awaitable 的公开文档。
- 验证方式：可独立编译的示例在 Docker `gcc:14` 镜像（Linux）与 Homebrew clang 22.1.7（libc++）下以 `-Wall -Wextra -Wpedantic -Werror` 编译并运行，包括写入后读回、短读报错、超大帧长被拒绝、C 头文件单独以 C11 编译。libFuzzer 入口按文档原样以 `-fsanitize=fuzzer,address,undefined` 构建并运行 20000 次。CUDA 示例未编译。
- 新增 `short-io` 案例的初始检查按设计失败；仓库外的参考解答在 GCC 14 下通过。
