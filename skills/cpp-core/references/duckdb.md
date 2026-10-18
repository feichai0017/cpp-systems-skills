# DuckDB 工程参考

DuckDB 是本合集的主要 C++ 工程参考。当前项目的合同、代码与工具约定优先；下面的事实来自官方固定源码，迁移建议是本合集的工程判断。

核对日期：2026-10-18。源码快照：[1b4c3e54ba3625bac56ad184f0ce642a8d2bfbd5](https://github.com/duckdb/duckdb/tree/1b4c3e54ba3625bac56ad184f0ce642a8d2bfbd5)。只代表列出的文件已阅读，没有构建或性能验证整个 DuckDB。

## 代码、错误与测试

[贡献指南](https://github.com/duckdb/duckdb/blob/1b4c3e54ba3625bac56ad184f0ce642a8d2bfbd5/CONTRIBUTING.md) 将独占所有权、可读控制流、内部断言和外部错误分开处理；其测试建议覆盖不正确用法与不同数据类型。

迁移到本项目：

- 资源有 owner、控制流能直接阅读，命名体现职责与单位；这些原则可以保留在日常编码底座。
- 输入错误必须通过运行时错误合同处理；断言针对程序错误，并说明所维护的不变量。不能把错误难以复现当作改为断言的充分理由。
- 优先通过能观察问题的稳定行为写回归，再按必要性进入底层；不把 DuckDB 的 SQL 测试框架变成其他项目的规定。
- 它对查询终止使用异常的策略，不覆盖项目现有 `Status` / `Result`；`idx_t`、公共字段布局、大小写、后缀和格式化版本也不是跨项目默认值。

## 安全包装有职责

[duckdb::vector](https://github.com/duckdb/duckdb/blob/1b4c3e54ba3625bac56ad184f0ce642a8d2bfbd5/src/include/duckdb/common/vector.hpp) 的索引、空容器访问与删除入口带有受模板参数/编译条件控制的检查，不只是把调用转发给标准容器。

迁移判断：删除 wrapper 前检查实际安全语义与构建条件；保留有职责的现有封装，也不因为 DuckDB 使用包装就为所有标准类型新增包装。是否在某个配置中启用、是否覆盖当前访问方式，需要看实际代码。

## 持有元数据与保持字节可读是不同职责

[BufferHandle 声明](https://github.com/duckdb/duckdb/blob/1b4c3e54ba3625bac56ad184f0ce642a8d2bfbd5/src/include/duckdb/storage/buffer/buffer_handle.hpp) 禁止复制、支持移动，并持有 `BlockHandle` 和 buffer node；[实现](https://github.com/duckdb/duckdb/blob/1b4c3e54ba3625bac56ad184f0ce642a8d2bfbd5/src/storage/buffer/buffer_handle.cpp) 在析构中调用 `Destroy()`，有效状态下调用 buffer manager 的 `Unpin()`。

迁移判断：读取借用需要覆盖最后访问的 pin/lease，不能只凭元数据对象仍存活就释放读保护。此例是进程内资源管理参考，不提供跨进程重启、远端 ACK 或设备 DMA 的完整保证。

## 区分表示、访问和物化

[Vector 接口](https://github.com/duckdb/duckdb/blob/1b4c3e54ba3625bac56ad184f0ce642a8d2bfbd5/src/include/duckdb/common/types/vector.hpp) 分开提供 `Reference`、`Slice`、`Flatten` 和 `ToUnifiedFormat`；[UnifiedVectorFormat](https://github.com/duckdb/duckdb/blob/1b4c3e54ba3625bac56ad184f0ce642a8d2bfbd5/src/include/duckdb/common/vector/unified_vector_format.hpp) 包含数据指针、选择索引、有效性信息和物理类型。

迁移判断：批处理接口先考虑能否使用统一访问合同，避免调用方便就强制展开数据。保留选择索引、有效性和底层 owner 的对应关系；有统一表示不意味着拥有数据，也不证明每种转换都没有分配或拷贝。

## 使用边界

先定位本项目的相同职责，再按需读上面的具体符号。引用时保留版本、观察到的机制与本地前提差异；采用前核对项目所需版本，不把“与成熟项目相似”当作正确性或性能证据。这里没有复制上游实现或引入 DuckDB 依赖。
