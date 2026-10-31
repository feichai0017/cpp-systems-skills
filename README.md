# cpp-systems-skills

面向 C++ 服务、缓存、存储与推理基础设施的 Agent Skills。日常编码在项目的 C++ 标准内使用现代写法，以简化实现、代码规范和语义命名为重点，正确组织头文件、源文件与构建依赖，保留必要的所有权、错误与并发边界；评审与性能结论须有可检查的证据。

[现代 C++ 写法](skills/cpp-core/references/modern-idioms.md) 按 C++17/20/23 列出可用设施、参数与所有权写法和常见旧式写法的替换；[设计范式](skills/cpp-core/references/design-paradigms.md) 说明值语义、构造即有效、RAII owner、选项结构、variant 状态、依赖注入、不可变快照与 Pimpl 的适用前提。[项目结构与文件摆放](skills/cpp-core/references/project-layout.md)、[CMake 参考](skills/cpp-core/references/build-cmake.md) 和 [Blade 参考](skills/cpp-core/references/build-blade.md) 覆盖目录布局、include 规则、模块分层、目标与依赖声明、第三方依赖管理和常用命令。推荐示例在 clang 22 与 GCC 14 下编译通过，CMake 示例项目完成过配置、构建、测试与安装导出。

以 [DuckDB 的工程实践](skills/cpp-core/references/duckdb.md) 为主要 C++ 参考，重点吸收断言边界、安全包装、pin 生命周期与数据表示设计；项目已有错误策略、基础类型和格式仍优先。

[项目与实现参考](skills/cpp-core/references/project-references.md) 列出 Core Guidelines、Google/Chromium 规范与按语言标准标注的现代代码库（Abseil、LLVM、RocksDB、Folly、Arrow、Velox、Mooncake、3FS、Seastar、ClickHouse 等）；[基础库选型](skills/cpp-core/references/library-selection.md) 先列标准库设施，再按职责给出 Abseil、fmt、spdlog、Boost、Folly、序列化、并发、分配器、压缩、测试与追踪等库的复用入口和前提。它们随 `cpp-core` 安装，仅在相应任务中读取，不是统一依赖清单。

[共享内存与状态服务先例](skills/cpp-core/references/shared-memory-state-precedents.md) 按实际场景定位 Vineyard、Ray Plasma、LMDB、iceoryx 和 iceoryx2 的固定源码版本。它区分可直接复用的库、必要的薄适配和只应借鉴的架构，并要求满足当前合同后停止扩展抽象。

中文规则正文，标准 `SKILL.md` 目录结构；每个技能自包含，可单独安装。项目现有 `AGENTS.md`、构建方式、`Status`/`Result`、命名与格式配置优先。不会要求升级语言标准、切换异常策略或全仓重命名。

## 技能选择

| 技能 | 使用场景 | 关键约束 |
| --- | --- | --- |
| [cpp-core](skills/cpp-core/SKILL.md) | 日常编写、修改 C++，新增文件与构建依赖 | 项目标准内的现代写法、简化实现、项目规范、准确命名；正确的文件位置与公开/私有依赖；先复用现有能力，保留必要安全边界 |
| [cpp-lifetime](skills/cpp-lifetime/SKILL.md) | 生命周期、异步、并发、SHM 与 I/O | 借用有效期、发布与回收、取消/完成竞争、跨边界合同 |
| [cpp-simplify](skills/cpp-simplify/SKILL.md) | 精简代码、清理冗余检查与包装 | 删除检查需要保证来源；抽象按职责判断，不按调用次数 |
| [cpp-review](skills/cpp-review/SKILL.md) | PR/MR、堆叠分支、本地改动评审 | 真实 base、分层 diff、有触发条件和影响的发现 |
| [cpp-validation](skills/cpp-validation/SKILL.md) | 构建（CMake、Blade 等）、回归、sanitizer、静态分析 | 风险对应验证、项目工具配置、执行结果与限制 |
| [cpp-performance](skills/cpp-performance/SKILL.md) | 性能问题、benchmark 与数据路径 | 同等工作量、实际完成计时、可比基线、实测与推断分开 |

日常编码以 `cpp-core` 为底座，普通写码默认检查实现是否直接、写法是否符合规范、命名是否准确，无需额外要求精简。专项任务选择对应技能，不要求每次加载全部六个；`cpp-simplify` 用于专门的精简任务。专项技能重复少量必要边界，以便单独安装，不依赖其他技能或专有工具。

## 主题覆盖

每个主题只在相关任务中读取；入口文件列出何时读取哪份参考。

| 主题 | 位置 |
| --- | --- |
| 现代写法、按标准的设施、常见旧式写法替换 | `cpp-core` · [现代 C++ 写法](skills/cpp-core/references/modern-idioms.md) |
| 类型与模块设计范式 | `cpp-core` · [设计范式](skills/cpp-core/references/design-paradigms.md) |
| 错误模型、系统错误、异常安全、`noexcept` | `cpp-core` · [错误处理](skills/cpp-core/references/error-handling.md) |
| 目录布局、头文件与 include 规则、模块分层 | `cpp-core` · [项目结构](skills/cpp-core/references/project-layout.md) |
| CMake 目标、依赖管理、presets、安装导出 | `cpp-core` · [CMake](skills/cpp-core/references/build-cmake.md) |
| Blade BUILD、头文件依赖检查、可见性、第三方库 | `cpp-core` · [Blade](skills/cpp-core/references/build-blade.md) |
| fd、`EINTR` 与短读写、`mmap`、时钟、信号、进程、epoll/io_uring | `cpp-core` · [OS 与 POSIX 接口](skills/cpp-core/references/os-interfaces.md) |
| socket、消息边界、背压、截止时间、重试、序列化演进 | `cpp-core` · [网络与 RPC](skills/cpp-core/references/networking.md) |
| `fsync`、原子替换、WAL、磁盘格式 | `cpp-core` · [存储与崩溃一致性](skills/cpp-core/references/storage-durability.md) |
| 分配器、对齐、对象与字节、整数溢出、迭代器失效 | `cpp-core` · [内存与对象模型](skills/cpp-core/references/memory-and-object-model.md) |
| ABI、符号可见性、C 接口、插件、Python/Rust 绑定 | `cpp-core` · [ABI 与互操作](skills/cpp-core/references/abi-and-interop.md) |
| 日志、指标、追踪、崩溃诊断 | `cpp-core` · [可观测性](skills/cpp-core/references/observability.md) |
| 不可信输入、密钥、随机数、编译加固 | `cpp-core` · [安全与加固](skills/cpp-core/references/security-hardening.md) |
| CUDA stream/event/内存与错误检查 | `cpp-core` · [CUDA C++](skills/cpp-core/references/cuda-cpp.md) |
| 标准库与第三方库选型、参考代码库 | `cpp-core` · [基础库选型](skills/cpp-core/references/library-selection.md)、[项目与实现参考](skills/cpp-core/references/project-references.md) |
| 寿命、发布与回收、取消竞争 | [cpp-lifetime](skills/cpp-lifetime/SKILL.md) |
| 协程与异步模型 | `cpp-lifetime` · [协程与异步](skills/cpp-lifetime/references/coroutines-and-async.md) |
| 线程池、关闭顺序、原子与无锁回收 | `cpp-lifetime` · [并发模式](skills/cpp-lifetime/references/concurrency-patterns.md) |
| 共享内存、RPC、DMA/RDMA 跨边界合同 | `cpp-lifetime` · [跨边界合同](skills/cpp-lifetime/references/cross-boundary.md) |
| 编译优化、剖析工具、缓存与 NUMA、构建时间 | `cpp-performance` · [工具链与性能剖析](skills/cpp-performance/references/toolchain-and-profiling.md) |
| 测试替身、确定的并发测试、故障注入、模糊测试 | `cpp-validation` · [测试策略](skills/cpp-validation/references/testing-strategies.md) |
| 未定义行为的类别与检测 | `cpp-validation` · [未定义行为](skills/cpp-validation/references/undefined-behavior.md) |
| sanitizer、clang-tidy、警告选项 | `cpp-validation` · [工具配置](skills/cpp-validation/references/tooling.md) |
| 评审范围与发现质量 | [cpp-review](skills/cpp-review/SKILL.md) |

不覆盖的内容：C++20 模块的工程化落地（工具链仍在成熟中）、非 NVIDIA 加速器、Windows 专有 API，以及具体业务领域的协议。

## 自动选择

六个技能都显式设置 `policy.allow_implicit_invocation: true`。Codex 可根据任务与 `description` 的匹配自动选用，无需每次写 `$cpp-core`；描述的开头保留最关键的场景词。`default_prompt` 只是手动调用的起始提示，不负责路由。[官方技能说明](https://learn.chatgpt.com/docs/build-skills)

如果希望“日常写 C++ 默认使用 cpp-core”成为个人默认约定，将 [全局指令片段](examples/AGENTS.codex-global.md) 合并到 `${CODEX_HOME:-$HOME/.codex}/AGENTS.md`，保留原有内容。它让写码任务默认使用底座、专项按场景加载；单靠允许隐式调用并不保证每轮都选中某个技能。[全局指令说明](https://learn.chatgpt.com/docs/agent-configuration/agents-md)

| 自然语言任务（无需技能名） | 预期选择 |
| --- | --- |
| “给这个 C++ 类加一个查询接口” | `cpp-core` |
| “修复回调晚到导致的 use-after-free” | `cpp-core` + `cpp-lifetime` |
| “清理这段 C++ 的多余包装和重复检查” | `cpp-core` + `cpp-simplify` |
| “审查这个 C++ MR 相对父分支的 diff” | `cpp-review` |
| “排查这个 C++ target 的 sanitizer 失败” | `cpp-validation`，实际改代码时补充 `cpp-core` |
| “分析这段 C++ 读路径的 p99 与拷贝成本” | `cpp-performance`，实际改代码时补充 `cpp-core` |

安装脚本只安装技能，不代替用户修改全局指令。全局 `AGENTS.md` 在新会话/运行启动时加载；技能文件支持自动刷新，未显示更新时重启 Codex。局部项目指令仍可覆盖全局默认；配置校验不等于真实任务选择的统计评估。

## 安装到 Codex

安装脚本需要 Python 3.10+。仓库公开，HTTPS 克隆不需要 GitHub 登录或 `gh`。评审范围工具与测试支持 Git 2.20+。

```sh
git clone https://github.com/feichai0017/cpp-systems-skills.git
cd cpp-systems-skills
python3 scripts/install.py --dest "${CODEX_HOME:-$HOME/.codex}/skills" --dry-run
python3 scripts/install.py --dest "${CODEX_HOME:-$HOME/.codex}/skills"
```

安装工具只复制本地技能目录，不联网、不修改项目配置。它在复制前检查全部目标；任一同名目录或链接已存在就拒绝覆盖。`--dry-run` 不创建目录。磁盘/权限等复制途中错误可能留下部分新目录，报错后应检查实际结果。

先用 `python3 --version` 确认版本；默认解释器过旧时，在下面的命令中使用已安装的 `python3.10` 或更新版本。工具会明确拒绝不支持的 Python 版本。

也可以只安装两个：

```sh
python3 scripts/install.py --dest "${CODEX_HOME:-$HOME/.codex}/skills" \
  --skill cpp-core --skill cpp-review
```

也支持 Codex 自带的 `$skill-installer`：提供本仓库及 `skills/cpp-core` 等目标路径。安装后在下一轮对话确认技能可见。

更新时先 `git pull --ff-only`，检查差异，再备份需要更新的已安装目录并移出安装位置，重新执行安装。工具不自动删除或合并已有技能，以保留本地定制。

其他支持 Agent Skills 的客户端可使用 `skills/<name>` 目录；UI 元数据位于 `agents/openai.yaml`。本仓库不宣称已在所有客户端测试。

## 使用示例

```text
用 $cpp-core 实现这个接口，遵循仓库现有 Status/Result 和命名约定。

用 $cpp-core 设计这个共享读组件，先查现有依赖，再核对相似开源实现的适用前提。

用 $cpp-core 设计 State/Compute 共享内存读路径，按失败模型选择源码先例，只实现现有库没有覆盖的职责。

用 $cpp-lifetime 检查取消请求与晚到回调的竞争，指出 owner 和最后使用点。

用 $cpp-simplify 精简当前改动；每个删除的检查都说明上游保证及有效范围。

用 $cpp-review 评审当前分支相对 origin/stack-parent 的改动，包含本地未提交内容。

用 $cpp-validation 选择并执行这次生命周期修改需要的验证，区分失败和未执行。

用 $cpp-performance 分析这段读路径，先画出实际数据搬运和 owner，再设计可比实验。
```

如需写入项目级约定，参考 [项目接入示例](examples/AGENTS.cpp.md)，根据仓库事实选择内容后合并；不要覆盖已有 `AGENTS.md`。

项目还没有静态检查配置时，可以从 [clang-tidy 示例](examples/clang-tidy.modern.yaml) 选择检查项：它只启用与现代写法直接对应、误报较少的检查，检查名在 clang-tidy 22 下核对过。先对改动文件运行，不要直接设为全仓 `WarningsAsErrors`。

## 工具与验证

评审范围工具位于 `cpp-review` 技能内部，单独安装该技能也可使用：

```sh
python3 skills/cpp-review/scripts/review_scope.py \
  --repo /path/to/project --scope all --base origin/stack-parent
```

它输出固定提交、merge-base、四层文件清单与补丁读取命令；不选择基线、不联网、不修改 Git 状态。`--scope branch` 支持单独评审指定 head，`--scope worktree` 只看当前 HEAD 的本地改动。无法解析的引用、非唯一 merge-base、与本地工作区不匹配的 head 会报错。

本地运行仓库检查：

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements-dev.txt
.venv/bin/python scripts/validate.py
.venv/bin/python -m unittest discover -s tests -v
```

GitHub Actions 在 Python 3.10 和 3.12 上运行相同检查。自动检查覆盖技能格式、每个技能的本地引用边界、UI 元数据、Git 范围解析与安装不覆盖行为。测试会单独安装每个技能再检查引用。它们不证明模型必然遵循指令，也不代表任何业务 C++ 项目已通过验证。

[行为评估案例](evals/behavior-cases.md) 提供独立试用的输入与判据；新增规则应优先由真实误用推动。工具检查、模型完成案例与技能带来的效果提升分别判断。

[原始代码案例](evals/fixtures/README.md) 把执行输入和评审判据分开。模型只接收选定案例和所需技能，不能读取评审判据；预期结果中包含无需修改代码的场景。

[自然语言选择案例](evals/automatic-selection.md) 单独检查未点名技能时的选择和边界；元数据通过不代表这些案例已经过模型评估。

仓库只维护评测输入、判据和可复用工具。每次运行的模型输出、补丁、日志、输入快照或摘要、成绩与实验报告保存到仓库外的临时目录或专用产物存储，不提交到本仓库。记录实际模型版本与技能提交；需要判断技能带来的提升时，再安排同模型、同任务的有无技能对照。

## 设计与来源

- [设计取舍](docs/design.md)：为什么是六个技能，哪些规则属于底座，哪些按场景加载。
- [参考来源](docs/sources.md)：用户提供的四个社区技能与官方文档，以及本合集的适配边界。

本合集为重新组织的原创指令和工具实现，未打包上游技能全文。没有内网地址、账号凭据或生产数据；具体项目知识留在相应项目中维护。
