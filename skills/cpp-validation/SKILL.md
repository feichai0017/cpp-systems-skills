---
name: cpp-validation
description: "C/C++ 构建或测试失败、验证方案、sanitizer、静态分析任务。根据实际风险执行项目已有检查并报告证据；普通编码中的轻量验证由默认编码流程完成。"
---

# C++ 构建与验证

验证改变的行为和关键合同，避免仪式化地跑所有工具。遵循项目要求；工具的缺失、环境故障和代码失败分别报告。

## 找到真实构建入口

- 查阅适用的 `AGENTS.md`、CI、构建脚本、presets、相关 target 与测试标签。不要假定 CMake，也不要凭空发明 target。
- 确认编译器版本、C++ 标准、关键宏、链接方式、Debug/Release、异常策略与目标架构；共享库/ABI 改动要覆盖相关消费者。项目支持多个编译器时，头文件和模板改动至少用其中两种编译（例如本机默认是 Clang 时再用 GCC），找不到第二种编译器时在报告中标为未执行。
- 有 `compile_commands.json` 时确认它对应当前源码与配置。静态分析解析错误先解决真实 include、宏与生成文件，不批量屏蔽。
- 保留既有 `.clang-format` / `.clang-tidy` 和命名约定；不默认写入 `Checks: '*'` 或全局 `WarningsAsErrors: '*'`。

常见构建系统的入口（以项目脚本和 CI 为准）：

| 构建系统 | 识别标志 | 构建与测试 | 编译数据库 |
| --- | --- | --- | --- |
| CMake | `CMakeLists.txt`、`CMakePresets.json` | `cmake --preset <name>`、`cmake --build --preset <name>`、`ctest --preset <name>`；没有 presets 时 `cmake -S . -B build -G Ninja` 后 `cmake --build build`、`ctest --test-dir build --output-on-failure` | `CMAKE_EXPORT_COMPILE_COMMANDS=ON` |
| Blade | 根目录 `BLADE_ROOT`、各目录 `BUILD` | `blade build //dir/...`、`blade test //dir/...`、`-p debug` 切换配置 | `blade dump --compdb --to-file compile_commands.json` |
| Bazel | `MODULE.bazel`/`WORKSPACE`、`BUILD.bazel` | `bazel build //...`、`bazel test //...` | 项目自带的生成规则 |

Blade 的 missing/unused dependency 和 `hdrs` 诊断属于构建结果的一部分，按依赖声明问题处理，不靠全局 include 路径或关闭检查消除。CMake 的配置阶段错误（找不到包、目标名拼错）与编译错误分开报告。

## 按风险选择验证

| 改动 | 首选验证 | 条件适用时补充 |
| --- | --- | --- |
| 局部无行为编辑 | 项目格式/编译检查 | 不强制新增测试 |
| 行为或错误处理修复 | 直接复现原问题的回归测试 | 无效输入、短读、失败后的状态 |
| owner / view / allocator | 寿命、移动、释放顺序与失败路径测试 | ASan/UBSan；对应 allocator 的覆盖限制 |
| 并发/异步状态机 | 可控交错、取消与终态竞争测试 | 独立 TSan 配置、稳定性测试 |
| SHM/RPC/设备协议 | 合同与故障注入测试 | 独立进程、重启、断链及真实设备 |
| 计算/布局/精度 | 有独立 oracle 的严格对照 | 边界形状、dtype、有效长度和约定容差 |
| 性能优化 | 行为等价验证 + 匹配环境的基线实验 | 真实负载与端到端指标 |
| 文件写入/持久化 | 短读写、`ENOSPC`、`fsync` 失败的注入测试 | 在写入各阶段终止进程后验证恢复 |
| 解析器/协议解码 | 边界与截断输入的回归测试 | libFuzzer + ASan/UBSan |

设计测试替身、确定的并发测试、故障注入、模糊测试或 sanitizer 矩阵时，读 [测试策略](references/testing-strategies.md)。问题只在特定优化级别或编译器下出现，或审查容易出现未定义行为的代码时，读 [未定义行为](references/undefined-behavior.md)。

测试必须观察外部行为或不变量，而不是照抄实现、匹配函数名或专为“测试变绿”改合同。测试不改动产品代码：不加测试专用的钩子、开关或分配器重定义；没有现成的替换点时，在报告中写明没有覆盖的失败路径。仅在需求本身允许时调整容差或部分结果语义。

优先在能观察该缺陷的稳定公共行为层复现，确需交错或内部状态时再使用底层测试。输入错误应验证实际错误结果；改变断言/运行时校验时，按风险覆盖断言被禁用的配置，避免 Debug 通过而 Release 失去保护。

## 工具使用

需要 sanitizer 或 clang 工具的具体取舍时，读 [工具配置与证据](references/tooling.md)。优先运行已有配置；必要的新配置保持局部、可解释，不覆盖原构建。

失败时先检查完整日志、退出码、失败层次和基线是否同样失败。缩小到最小相关 target 或测试；避免把不可用依赖归咎于改动，也不能因此把检查记为通过。

若测试仍在运行，等待实际结束再写“通过”。被中止、超时、未执行和失败均不是成功。重复运行只有在排查间歇性或验证重复性时才有意义。

## 交付证据

记录命令、工作目录/commit、构建配置、退出状态、测试结果和必要日志路径。根据任务规模保持简短。

明确区分：

- 源码检查支持的判断；
- 当前环境实际通过的测试；
- 每条失败路径是否测试过：测过的写出具体触发方式（替换点或替身、构造的输入、失败的是哪一步），没测的写出原因；
- 真实硬件/跨进程/集成环境已验证的行为；
- 环境缺失或尚未执行的检查及其影响。

必要检查通过后推进交付；只有新变化、失败或尚未解决的风险才扩大或重复验证。
