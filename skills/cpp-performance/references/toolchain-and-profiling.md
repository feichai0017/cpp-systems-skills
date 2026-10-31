# 工具链与性能剖析

选择编译优化选项、使用 profiler 定位成本、分析缓存/NUMA/内存问题，或缩短构建时间时阅读。所有结论仍按本技能的可比实验要求验证。

## 编译选项

| 选项 | 说明 |
| --- | --- |
| `-O2` | 默认的发布优化级别；`-O3` 不一定更快，按基准对比后决定 |
| `-march=native` | 只适合在同一类机器上构建和运行；分发的二进制改用明确的目标（如 `-march=x86-64-v3`）或运行时分派 |
| `-g` / `-g1` | 发布构建保留调试信息（可拆分到独立文件），便于剖析与崩溃分析 |
| `-fno-omit-frame-pointer` | 让 `perf` 等基于帧指针的栈回溯可靠；开销通常很小 |
| LTO / ThinLTO（`-flto`、`-flto=thin`） | 跨编译单元内联；增加链接时间，所有对象和静态库要一致地使用 |
| PGO（`-fprofile-generate`/`-fprofile-use`，Clang 也支持采样式 AutoFDO） | 用真实负载的剖析数据指导优化；剖析负载要能代表生产 |
| BOLT（`llvm-bolt`） | 链接后按剖析数据重排代码布局，适合大型二进制 |

对比优化选项时，基线与候选只差这一个选项，其他编译配置、依赖与运行环境保持一致。sanitizer 和加固选项会改变性能，不与普通构建混合比较。

## CPU 剖析

- `perf record -g`（或 `--call-graph dwarf`）采样调用栈，生成火焰图查看热点；`perf stat -e cycles,instructions,cache-misses,branch-misses` 查看硬件计数。
- `perf c2c` 定位伪共享：多个核心反复争用同一缓存行。
- `valgrind --tool=callgrind`/`cachegrind` 提供确定的指令与缓存模拟结果，运行慢，适合对比小范围修改。
- Intel VTune、AMD uProf 提供更细的微架构分析。
- 应用内的低开销计时用 Tracy 或 Perfetto 一类工具标记区间。

剖析的是优化后的构建，并保留符号；剖析结果给出“时间花在哪里”，收益仍要用可比的基准确认。

## 内存剖析

- 分配次数与热点：heaptrack、jemalloc/tcmalloc 自带的堆剖析、`valgrind --tool=massif`。
- 驻留内存（RSS）与虚拟内存分开看；分配器可能没有把释放的内存归还给系统，这不等于泄漏。
- 泄漏用 ASan/LSan 检查，而不是只看 RSS 曲线。

## 内核与 I/O

- `bpftrace`/eBPF 可以统计系统调用延迟、块设备 I/O 延迟、调度延迟，而无需修改程序。
- `iostat`、`pidstat`、`/proc/<pid>/io` 查看 I/O 吞吐与等待；区分页缓存命中与真实设备读取。
- 测量 I/O 优化时记录文件系统、设备型号、队列深度与缓存状态。

## 缓存、内存布局与 NUMA

- 数据布局影响缓存命中：热路径上只读取需要的字段时，结构体数组拆成数组结构体（SoA）可能更快；先用计数器确认缓存未命中是主要成本。
- 分支预测提示（`[[likely]]`/`[[unlikely]]`）只在剖析证明有效时使用。
- 大页（透明大页或显式 hugetlbfs）可以减少 TLB 未命中，但会影响内存回收与延迟抖动；用实际负载对比。
- NUMA：内存默认分配在首次访问它的线程所在节点（first-touch）。线程与其主要访问的内存放在同一节点（`numactl`、libnuma），跨节点访问在计数器中可见。
- GPU 与网卡的 NUMA 位置同样重要：主机缓冲区放在与设备相同的节点上。

## 构建时间

- 编译缓存：ccache 或 sccache（通过 `CMAKE_CXX_COMPILER_LAUNCHER` 或构建系统配置）。
- 更快的链接器：`lld` 或 `mold`（`-fuse-ld=lld`），对大型 C++ 项目的增量构建效果明显。
- 减少头文件依赖：前置声明、Pimpl、把实现移出头文件、清理多余的 include（include-what-you-use、clang-tidy `misc-include-cleaner`）。
- 预编译头（CMake `target_precompile_headers`）和 unity build（`UNITY_BUILD`）可以显著加速，但会掩盖缺失的 include，CI 中保留一个不使用它们的构建。
- 模板密集的代码可以在 `.cc` 中显式实例化常用类型，并在头文件中 `extern template` 声明。
- 用 `-ftime-trace`（Clang）找出编译最慢的头文件和模板。
- C++20 模块可以从根本上减少重复解析，但编译器与构建系统支持仍在成熟中，引入前在目标工具链上验证。
