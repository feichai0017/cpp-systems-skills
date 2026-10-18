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

## 实现参考

[复用与源码参考](../skills/cpp-core/references/reuse-and-precedents.md) 在 DuckDB 工程参考之外，按问题补充 Folly、Boost.Interprocess、Seastar、Tokio 和 Crossbeam 的源码入口。此前已核对这些入口中的相关实现，索引用于发现机制与前提，不代表它们适合任意项目。

这些入口指向移动分支。实际采用时记录本次读取的 commit/tag、文件/符号与本地差异。没有复制这些项目的代码，也不以其成熟度或上游 benchmark 作为本项目的正确性或性能证据。

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
