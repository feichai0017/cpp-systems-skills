# 原始代码案例

案例代码为本合集编写的小项目，不依赖真实业务仓库。各案例的 C++ 标准写在其 `AGENTS.md` 中：`standard-gate` 为 C++14，`owner`、`reuse`、`borrow`、`naming` 为 C++17，其余为 C++20。

执行者只接收一个案例目录、指定技能目录和该案例的 `TASK.md` 内容。将这些文件复制到独立临时目录后开始新会话，不附带本文件、[评审判据](../fixture-rubric.md)、`../hidden-checks/` 或之前的诊断。不要通过共享父目录暴露判据。

## 第一轮：单点写法

| 案例 | 技能 | 任务材料 |
| --- | --- | --- |
| `reuse` | `cpp-core` | [任务](reuse/TASK.md)、现有工具、操作实现和行为检查 |
| `borrow` | `cpp-simplify` | [任务](borrow/TASK.md)、只读窗口、借用 owner 和检查 |
| `naming` | `cpp-core` | [任务](naming/TASK.md)、公开接口与调用方 |
| `owner` | `cpp-core` | [任务](owner/TASK.md)、模拟的外部 C 接口、泄漏的加载函数和检查 |
| `views` | `cpp-core` | [任务](views/TASK.md)、复制数据的旧式接口、项目 `Result` 和调用方 |
| `standard-gate` | `cpp-core` | [任务](standard-gate/TASK.md)、固定 C++14 的注册表、既有查找约定和检查 |
| `short-io` | `cpp-core` | [任务](short-io/TASK.md)、可注入的写函数、只发出部分数据的发送函数和检查 |

`reuse`、`owner` 和 `short-io` 初始版本有待修复的行为，其他案例初始检查应通过；不要把预期的初始失败当作合集工具测试失败。编译命令带 `-Werror`；评审时可再用 `examples/clang-tidy.modern.yaml` 检查改动文件，作为辅助证据而不是唯一判据。

## 第二轮：现象描述与隐藏检查

第一轮的任务直接描述了要做什么，强模型不用技能也能完成。第二轮的 `TASK.md` 只描述现象（崩溃、掉电后读到空文件、ASan 报告），可见检查只覆盖最直接的症状；更严格的条件放在 `../hidden-checks/<案例>/`，只由评审者在执行结束后运行。

| 案例 | 主要技能 | 任务材料 | 隐藏检查 |
| --- | --- | --- | --- |
| `cmake-module` | `cpp-core` | [任务](cmake-module/TASK.md)、带内部 CRC 库的 CMake 项目 | 文件位置、`PRIVATE` 依赖、CRC 复用；ASan/UBSan 下的对抗性记录 |
| `durable-config` | `cpp-core` | [任务](durable-config/TASK.md)、项目文件系统层、原地覆盖写入的配置保存 | 记录调用顺序（临时文件、`Sync`、`Rename`、目录 `Sync`）与故障注入 |
| `coro-lifetime` | `cpp-lifetime`、`cpp-core` | [任务](coro-lifetime/TASK.md)、惰性 `Task`、手动执行器、批量写入 | ASan 下先创建后等待的 `Put` |
| `frame-decoder` | `cpp-core` | [任务](frame-decoder/TASK.md)、把字节强转成结构体的解码器 | ASan/UBSan、非对齐输入、超大长度、20 秒 libFuzzer |
| `abi-review` | `cpp-review` | [任务](abi-review/TASK.md)、由 `setup.sh` 生成的 `v1.0..feature` 历史 | 评审文本的关键词定位，结论按判据人工判断 |

- `abi-review` 的 `setup.sh` 在评测工作区中用 `base/` 与 `head/` 生成 git 历史后删除自身；不要直接在仓库内运行它。
- 使用 AddressSanitizer 的案例用 `$CXX` 编译。在 macOS 26.6 上观察到 Apple clang 17 生成的任何 ASan 程序都会挂起，而 Homebrew LLVM 正常，这时把 `CXX` 设为可用的编译器并记录在运行元数据中。
- 每个隐藏检查都在原始案例上失败、在仓库外的参考解答上通过；`coro-lifetime` 另外确认了只在调用处保存 key 的修法能通过可见检查但不能通过隐藏检查。

## 运行与记录

`scripts/run_codex_eval.py` 为单个案例准备隔离工作区并运行 Codex：

```sh
python3 scripts/run_codex_eval.py durable-config --arm skills --trial 1 \
  --out /tmp/cpp-skill-evals --effort high --cxx /opt/homebrew/opt/llvm/bin/clang++ --grade
```

- `--arm skills` 把技能（默认全部）复制到工作区的 `.agents/skills`，并写入 `.git/info/exclude`，不进入评审的 diff；`--arm control` 不安装技能。
- 输出目录必须在仓库外。每次运行保存事件日志、最终回复、diff、`run.json`（Codex 版本、技能提交、读取过的技能文件等）和可选的 `grade.txt`。
- 需要判断技能带来的提升时，同一模型、同一设置下有无技能各运行多次，按次数报告每项判据的满足情况；少量运行只说明观察到的差异，不写成统计结论。

这些案例用于发现行为问题。运行产物、成绩和报告保存在仓库外，本目录只维护原始案例。
