# 基础库选型

仅在现有能力有缺口、需要选择或替换基础组件时使用。先查仓库、已引入依赖和当前标准库；满足合同就停止选型。下面是候选入口，不是要求全部安装的工具栈。

资料核对日期：2026-10-31。具体模块、语言标准和构建条件按目标工程固定版本核对；上游功能与 benchmark 不构成本项目的正确性或性能证据。引入方式（vcpkg、Conan、FetchContent、Blade `vcpkg#` 或 `thirdparty/`）见构建参考。

## 先用标准库

| 需求 | 标准设施 | 标准不够时 |
| --- | --- | --- |
| 可失败返回值 | C++23 `std::expected` | [tl::expected](https://github.com/TartanLlama/expected)、项目 `Status`/`Result`、`absl::StatusOr`（项目已用 Abseil 时） |
| 连续序列借用 | C++20 `std::span` | `absl::Span`、[Microsoft GSL](https://github.com/microsoft/GSL) 的 `gsl::span` |
| 范围算法 | C++20 `std::ranges` | [range-v3](https://github.com/ericniebler/range-v3) |
| 格式化与输出 | C++20 `std::format`、C++23 `std::print` | [{fmt}](https://fmt.dev/latest/) |
| 文件系统 | C++17 `std::filesystem` | — |
| 时间与时长 | `std::chrono`；C++20 日历与时区（库支持较晚） | [date](https://github.com/HowardHinnant/date) |
| 多维视图 | C++23 `std::mdspan` | [kokkos/mdspan](https://github.com/kokkos/mdspan) |

特性是否可用以 `<version>` 中的 `__cpp_lib_*` 宏和目标工具链为准。

## 按职责选择

| 需求 | 候选与入口 | 使用前确认 |
| --- | --- | --- |
| 格式化 | [{fmt}](https://fmt.dev/latest/) | 当前标准库格式化能力是否已足够；沿用已有格式化接口与错误策略，避免只做转发的包装层 |
| 日志 | [spdlog](https://github.com/gabime/spdlog)、[异步日志](https://github.com/gabime/spdlog/wiki/Asynchronous-logging) | 是否已有日志体系；多/单线程 logger、sink、异步队列的满载策略和退出 flush 合同，避免并行引入第二套日志 |
| 哈希容器与通用工具 | [Abseil 指南](https://abseil.io/docs/cpp/guides/)、[容器](https://abseil.io/docs/cpp/guides/container)；[Boost.Unordered](https://www.boost.org/doc/libs/latest/libs/unordered/doc/html/unordered.html) 的 `unordered_flat_map`（Boost 1.81+） | flat 容器 rehash 后元素地址失效；字符串、时间等工具按已启用模块复用。已有错误框架时不另引入 `Status` / `StatusOr` |
| 小对象与有序平面容器 | [Boost.Container](https://www.boost.org/doc/libs/latest/doc/html/container.html) 的 `small_vector`、`flat_map`；`absl::InlinedVector` | 内联容量、插入复杂度、迭代器失效规则与标准容器不同 |
| 网络、定时器与异步 I/O | [Boost.Asio](https://www.boost.org/doc/libs/latest/doc/html/boost_asio.html)、[异步模型](https://www.boost.org/doc/libs/latest/doc/html/boost_asio/overview.html) | 执行器、回调线程、buffer 寿命、取消与实际完成；已有运行时能完成任务时继续复用，不为一个接口另建事件循环 |
| io_uring | [liburing](https://github.com/axboe/liburing) | 内核版本与特性探测、注册 buffer/文件的寿命、取消后的实际完成 |
| 每核分片运行时 | [Seastar](https://github.com/scylladb/seastar) | 需要接受其线程、内存与调度模型；不能把片段放进任意线程池 |
| 共享内存地址表示与基础设施 | [Boost.Interprocess](https://www.boost.org/doc/libs/latest/doc/html/interprocess.html)、[`offset_ptr` 文档](https://www.boost.org/doc/libs/latest/doc/html/interprocess/offset_ptr.html)与[源码](https://github.com/boostorg/interprocess/blob/develop/include/boost/interprocess/offset_ptr.hpp) | 不同映射地址、布局、allocator 和同步前提；对象相对偏移不等于 region-relative offset，进程死亡恢复与协议版本仍由项目定义 |
| 资源 guard | 项目已有 ScopeExit；`absl::Cleanup`；Folly [`ScopeGuard`](https://github.com/facebook/folly/blob/main/folly/ScopeGuard.h) | 回滚 guard 的构造、移动、dismiss 和析构 |
| 并发组件 | [Folly 组件索引](https://github.com/facebook/folly/blob/main/folly/docs/Overview.md)、[oneTBB](https://github.com/uxlfoundation/oneTBB)、[moodycamel::ConcurrentQueue](https://github.com/cameron314/concurrentqueue) | 容量、生产者/消费者模型、阻塞与公平性；不能只凭“无锁/高性能”选型 |
| 内存分配器 | [jemalloc](https://github.com/jemalloc/jemalloc)、[mimalloc](https://github.com/microsoft/mimalloc)、[tcmalloc](https://github.com/google/tcmalloc) | 全进程替换的影响、与 sanitizer 的兼容、内存归还策略；用真实负载对比 |
| 命令行参数 | [CLI11](https://github.com/CLIUtils/CLI11)、[cxxopts](https://github.com/jarro2783/cxxopts) | 已有 gflags/absl flags 时继续沿用 |
| JSON | [nlohmann/json](https://github.com/nlohmann/json)（易用）、[simdjson](https://github.com/simdjson/simdjson)（高速只读解析） | 解析结果是否借用输入 buffer；热路径的分配与拷贝 |
| YAML / TOML | [yaml-cpp](https://github.com/jbeder/yaml-cpp)、[toml++](https://github.com/marzer/tomlplusplus) | 错误报告方式与异常策略 |
| 序列化与 RPC | [protobuf](https://github.com/protocolbuffers/protobuf)、[gRPC](https://github.com/grpc/grpc)、[FlatBuffers](https://github.com/google/flatbuffers)、[Cap'n Proto](https://github.com/capnproto/capnproto) | 兼容演进规则、零拷贝读取的 buffer 寿命、代码生成接入构建系统 |
| 压缩与校验 | [zstd](https://github.com/facebook/zstd)、[lz4](https://github.com/lz4/lz4)、[xxHash](https://github.com/Cyan4973/xxHash)、[crc32c](https://github.com/google/crc32c) | 格式版本与跨语言一致性；哈希不能替代加密校验 |
| SIMD | [Highway](https://github.com/google/highway)、[xsimd](https://github.com/xtensor-stack/xsimd) | 运行时分派与目标指令集；先确认编译器自动向量化不够 |
| GPU 基础库 | [CCCL](https://github.com/NVIDIA/cccl)（Thrust、CUB、libcu++）、[CUTLASS](https://github.com/NVIDIA/cutlass) | CUDA 版本、目标架构、编译时间 |
| Python 绑定 | [pybind11](https://github.com/pybind/pybind11)、[nanobind](https://github.com/wjakob/nanobind) | GIL 释放、对象寿命跨语言传递、ABI 与 Python 版本矩阵 |
| 枚举反射 | [magic_enum](https://github.com/Neargye/magic_enum) | 编译时间与枚举值范围限制 |
| 指标与追踪 | [prometheus-cpp](https://github.com/jupp0r/prometheus-cpp)、[OpenTelemetry C++](https://github.com/open-telemetry/opentelemetry-cpp)、[Tracy](https://github.com/wolfpld/tracy)、[Perfetto SDK](https://perfetto.dev/docs/instrumentation/tracing-sdk) | 热路径开销、采样与导出线程；已有监控体系时沿用 |
| 行为测试 | [GoogleTest/GoogleMock](https://github.com/google/googletest/blob/main/docs/primer.md)、[Catch2](https://github.com/catchorg/Catch2)、[doctest](https://github.com/doctest/doctest) | 沿用已有框架；用行为断言和 fixture 覆盖真实合同，避免为局部修改引入第二套测试体系 |
| 模糊测试 | [libFuzzer](https://llvm.org/docs/LibFuzzer.html) | 解析器和协议边界的输入覆盖；与 sanitizer 组合使用 |
| 局部性能测量 | [Google Benchmark](https://github.com/google/benchmark/blob/main/docs/user_guide.md)、[nanobench](https://github.com/martinus/nanobench) | 预热、重复、输入规模、分配成本与编译器优化；异步任务计时覆盖实际完成，端到端收益另测 |

## 容易改变合同的选择

- **容器替换**：查调用方是否保存元素地址、引用或迭代器。Abseil `flat_hash_map` / `flat_hash_set` rehash 会使元素地址失效，`node_hash_map` / `node_hash_set` 可以保持元素地址但 rehash 仍使迭代器失效；不能把这些容器当作标准无序容器的无条件替代。
- **依赖与 ABI**：确认模块实际链接到目标，并统一版本和相关构建配置。[Abseil](https://abseil.io/about/compatibility) 和 [Folly](https://github.com/facebook/folly#build-notes) 均不承诺不同版本/提交间的 ABI 兼容；共享库、插件和动态加载场景不能默认混用二进制。
- **异步资源**：取消请求不自动证明最后一次 buffer 访问已经结束；采用库时仍要把 owner、借用和完成通知接入本项目的关闭协议。
- **跨进程数据**：区分进程本地句柄与共享布局；偏移指针只解决其定义的寻址问题，不能代替 generation、访问保护、回收确认或崩溃恢复。
- **全进程影响**：分配器、日志、信号处理和线程池会影响整个进程，引入前确认与已有组件不冲突。
- **引入成本**：Folly、Asio、Seastar 等需要与工具链、依赖图及运行时相容。不要为一个局部 helper 引入整套框架，也不要未经核对就摘抄内部实现。

选择结果只需说明实际采用的模块/符号、版本依据、关键前提及需要验证的合同。依赖足够时直接调用；确有错误转换、资源持有或平台隔离职责时再写适配层。

若只是学习机制或代码组织，使用 [项目与实现参考](project-references.md)。复制适配源码、只参考设计与引入依赖的检查方法见 [复用与源码参考](reuse-and-precedents.md)。
