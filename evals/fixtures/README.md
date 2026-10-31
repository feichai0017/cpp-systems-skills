# 原始代码案例

案例代码为本合集编写的小项目，不依赖真实业务仓库。各案例的 C++ 标准写在其 `AGENTS.md` 中：`standard-gate` 为 C++14，`views` 为 C++20，其余为 C++17。

执行者只接收一个案例目录、指定技能目录和该案例的 `TASK.md` 内容。将这些文件复制到独立临时目录后开始新会话，不附带本文件、[评审判据](../fixture-rubric.md) 或之前的诊断。不要通过共享父目录暴露判据。

| 案例 | 技能 | 任务材料 |
| --- | --- | --- |
| `reuse` | `cpp-core` | [任务](reuse/TASK.md)、现有工具、操作实现和行为检查 |
| `borrow` | `cpp-simplify` | [任务](borrow/TASK.md)、只读窗口、借用 owner 和检查 |
| `naming` | `cpp-core` | [任务](naming/TASK.md)、公开接口与调用方 |
| `owner` | `cpp-core` | [任务](owner/TASK.md)、模拟的外部 C 接口、泄漏的加载函数和检查 |
| `views` | `cpp-core` | [任务](views/TASK.md)、复制数据的旧式接口、项目 `Result` 和调用方 |
| `standard-gate` | `cpp-core` | [任务](standard-gate/TASK.md)、固定 C++14 的注册表、既有查找约定和检查 |

运行案例内 `AGENTS.md` 的编译/检查命令。`reuse` 和 `owner` 初始版本有待修复的行为，其他案例初始检查应通过；不要把预期的初始失败当作合集工具测试失败。

`owner`、`views` 和 `standard-gate` 检查现代写法与标准边界：是否用 RAII 与返回值代替手动释放和输出参数，是否用借用视图代替复制，是否在固定的旧标准下不使用更高标准的设施。编译命令带 `-Werror`；评审时可再用 `examples/clang-tidy.modern.yaml` 检查改动文件，作为辅助证据而不是唯一判据。

这些案例用于发现行为问题，不提供统计通过率。评估记录模型及宿主版本、准确输入、skill/案例快照、修改、命令、结果和未覆盖限制，保存在仓库外；本目录只维护原始案例。需要判断技能带来的提升时，安排同模型、同任务的有无技能对照。使用支持模型标识的运行器；标识不可用时如实记录。
