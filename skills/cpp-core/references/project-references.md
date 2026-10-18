# 项目与实现参考

在需要比较接口、工程风格或某个系统机制时使用。日常小修改先看当前项目；根据问题选少量条目，不依次研究整张表。

资料核对日期：2026-10-18。以下是官方文档与相关接口的定位索引，推荐用途是本合集的工程判断；不代表完成了这些项目的全量源码审计、构建或性能验证。实际采用前按 [源码研究流程](reuse-and-precedents.md) 固定版本、读取相关实现与测试。

## C++ 项目

| 项目与入口 | 适合研究的问题 | 迁移边界 |
| --- | --- | --- |
| [DuckDB 工程参考](duckdb.md) | 日常工程规范、断言与输入错误、安全包装、buffer pin 和向量表示 | 主要外部规范参考；沿用当前项目的错误策略、类型和格式 |
| [LLVM Coding Standards](https://llvm.org/docs/CodingStandards.html)、[Programmer's Manual](https://llvm.org/docs/ProgrammersManual.html) | 语义命名、库分层、自包含头文件、提前返回；`StringRef` / `ArrayRef` 的借用接口和 `SmallVector` 的存储取舍 | 工程规范的重要补充；不为一个容器引入完整 LLVM，不照搬基础类型、命名形式或异常策略 |
| [LevelDB](https://github.com/google/leveldb)、[`Slice`](https://github.com/google/leveldb/blob/main/include/leveldb/slice.h) | 克制的接口、借用合同、批量写入和快照；适合从较小的存储系统理解职责划分 | `Slice` 不持有底层存储；学习接口不意味着复制旧式资源管理。官方仅做有限维护，新依赖选择需另行评估 |
| [RocksDB Overview](https://github.com/facebook/rocksdb/wiki/RocksDB-Overview) | WAL、`WriteBatch`、`Snapshot` / `Iterator` 与 compaction；逻辑可见性和物理资源保留 | Iterator 保留相关文件与 Snapshot 保护可见版本是不同机制；不能把数据库快照等同于 buffer pin，也不整体复制复杂后台架构 |
| [Apache Arrow C++ 内存管理](https://arrow.apache.org/docs/cpp/memory.html) | `Buffer`、`SliceBuffer`、`MemoryPool`、设备内存；批量数据布局、分配和拷贝边界 | 切片可避免这一步的数据复制，仍需证明底层 owner 和后续路径；已有依赖可复用，新增时比较实际数据处理/互操作需求与依赖成本 |
| [Seastar shared-nothing](https://seastar.io/shared-nothing/)、[`sharded`](https://github.com/scylladb/seastar/blob/master/include/seastar/core/sharded.hh) | 每核分片、跨核调用、分片服务的创建与停止 | 所有权和关闭顺序值得参考；采用运行时需要接受其线程、调度和跨核通信模型，不能将片段直接放进任意线程池 |

## 从参考中得到具体决策

- 学习接口如何表达动作、单位、借用和完成点，以及注释如何解释不变量；排版和大小写继续交给本项目规则。
- 读数据通路及其 owner，而不只看类名：例如 `StringRef` / `ArrayRef` / `Slice` 是借用，不能替代持有底层资源的句柄。
- 区分业务状态和物理资源：快照可见性、文件保留、buffer pin、I/O 完成保护各有职责，不能因为都使用引用计数就合并。
- 对照构造失败、取消、关闭与并发修改路径，确认先例的保证在本项目中由谁建立。没有同样的前提，就只采用适用的局部机制。
- 需要直接使用工具组件时转到 [基础库选型](library-selection.md)；可读的源码与合适的依赖是分别评估的结论。

## Rust 机制补充

这些入口保留用于比较所有权设计，不用于替换当前 C++ 项目的语言或运行时。

| 问题 | 入口 | 对照重点 |
| --- | --- | --- |
| 可跨任务移动的额度 | [Tokio semaphore](https://github.com/tokio-rs/tokio/blob/master/tokio/src/sync/semaphore.rs) | `OwnedSemaphorePermit` 随 owner 移动并在 Drop 归还；不等于远端 lease 已收到 release ACK |
| 读保护和延迟回收 | [Crossbeam epoch Guard](https://github.com/crossbeam-rs/crossbeam/blob/master/crossbeam-epoch/src/guard.rs) | 保护读者与延迟释放的配合；线程内 epoch 不提供进程死亡恢复 |

C++ 如何维持相同不变量，见 [借鉴 Rust 的设计](reuse-and-precedents.md#借鉴-rust-的设计)。
