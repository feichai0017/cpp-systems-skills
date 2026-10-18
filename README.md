# cpp-systems-skills

面向 C++ 服务、缓存、存储与推理基础设施的 Agent Skills。目标是明确所有权和错误合同、控制抽象成本，并让评审与性能结论有可检查的证据。

中文规则正文，标准 `SKILL.md` 目录结构；每个技能自包含，可单独安装。项目现有 `AGENTS.md`、构建方式、`Status`/`Result`、命名与格式配置优先。不会要求升级语言标准、切换异常策略或全仓重命名。

## 技能选择

| 技能 | 使用场景 | 关键约束 |
| --- | --- | --- |
| [cpp-core](skills/cpp-core/SKILL.md) | 日常编写、修改 C++ | 值语义、资源 owner、类型不变量、显式错误、最小必要实现 |
| [cpp-lifetime](skills/cpp-lifetime/SKILL.md) | 生命周期、异步、并发、SHM 与 I/O | 借用有效期、发布与回收、取消/完成竞争、跨边界合同 |
| [cpp-simplify](skills/cpp-simplify/SKILL.md) | 精简代码、清理冗余检查与包装 | 删除检查需要保证来源；抽象按职责判断，不按调用次数 |
| [cpp-review](skills/cpp-review/SKILL.md) | PR/MR、堆叠分支、本地改动评审 | 真实 base、分层 diff、有触发条件和影响的发现 |
| [cpp-validation](skills/cpp-validation/SKILL.md) | 构建、回归、sanitizer、静态分析 | 风险对应验证、项目工具配置、执行结果与限制 |
| [cpp-performance](skills/cpp-performance/SKILL.md) | 性能问题、benchmark 与数据路径 | 同等工作量、实际完成计时、可比基线、实测与推断分开 |

日常编码以 `cpp-core` 为底座；专项任务选择对应技能，不要求每次加载全部六个。专项技能重复少量必要边界，以便单独安装，不依赖其他技能或专有工具。

## 安装到 Codex

需要 Python 3.10+。仓库为私有，克隆前需要拥有访问权限及有效的 GitHub 登录。

```sh
gh repo clone feichai0017/cpp-systems-skills
cd cpp-systems-skills
python3 scripts/install.py --dest "${CODEX_HOME:-$HOME/.codex}/skills" --dry-run
python3 scripts/install.py --dest "${CODEX_HOME:-$HOME/.codex}/skills"
```

安装工具只复制本地技能目录，不联网、不修改项目配置。它在复制前检查全部目标；任一同名目录或链接已存在就拒绝覆盖。`--dry-run` 不创建目录。磁盘/权限等复制途中错误可能留下部分新目录，报错后应检查实际结果。

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

用 $cpp-lifetime 检查取消请求与晚到回调的竞争，指出 owner 和最后使用点。

用 $cpp-simplify 精简当前改动；每个删除的检查都说明上游保证及有效范围。

用 $cpp-review 评审当前分支相对 origin/stack-parent 的改动，包含本地未提交内容。

用 $cpp-validation 选择并执行这次生命周期修改需要的验证，区分失败和未执行。

用 $cpp-performance 分析这段读路径，先画出实际数据搬运和 owner，再设计可比实验。
```

如需写入项目级约定，参考 [项目接入示例](examples/AGENTS.cpp.md)，根据仓库事实选择内容后合并；不要覆盖已有 `AGENTS.md`。

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

GitHub Actions 运行相同检查。自动检查覆盖技能格式、内部链接、UI 元数据、Git 范围解析与安装不覆盖行为。它们不证明模型必然遵循指令，也不代表任何业务 C++ 项目已通过验证。

[行为评估案例](evals/behavior-cases.md) 提供独立试用的输入与判据；新增规则应优先由真实误用推动。模型评估的执行记录应与结构校验分开。

## 设计与来源

- [设计取舍](docs/design.md)：为什么是六个技能，哪些规则属于底座，哪些按场景加载。
- [参考来源](docs/sources.md)：用户提供的四个社区技能与官方文档，以及本合集的适配边界。

本合集为重新组织的原创指令和工具实现，未打包上游技能全文。没有内网地址、账号凭据或生产数据；具体项目知识留在相应项目中维护。
