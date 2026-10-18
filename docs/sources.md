# 参考来源与改写边界

整理日期：2026-10-18。入口来自用户给出的比较材料；下面记录来源和适配理由，不将社区文章当作 C++ 语言标准。

| 来源 | 采用的方向 | 本合集的适配 |
| --- | --- | --- |
| [ECC cpp-coding-standards](https://github.com/affaan-m/ECC/blob/main/skills/cpp-coding-standards/SKILL.md) | 资源安全、值语义、类型与接口合同 | 项目错误策略、命名、文件后缀和语言标准优先；不搬入整套风格 |
| [DeevsDeevs anti-ai-slop](https://github.com/DeevsDeevs/agent-system/blob/HEAD/anti-ai-slop/SKILL.md) | 按用户材料描述，审视冗余检查、异常层与包装 | 删除前证明保证；评审范围显式选择，保留所有相关 diff 层 |
| [karpathy-guidelines](https://github.com/multica-ai/andrej-karpathy-skills/blob/main/skills/karpathy-guidelines/SKILL.md) | 控制任务范围，以可验证结果驱动实现 | 不按调用次数否定抽象；一次性 RAII 仍可能有实际职责 |
| [Jeffallan cpp-pro](https://github.com/Jeffallan/claude-skills/blob/main/skills/cpp-pro/SKILL.md) | 按需查询现代 C++、并发与工具 | 特性与工具服从任务和项目，不预设 concepts 或统一新构建配置 |

ECC 与 karpathy-guidelines 的原始用户链接分别重定向到上表地址。前三者中的 anti-ai-slop 链接在本次读取未成功返回正文，其观点只依据用户提供的摘要，没有宣称完成独立源码核验。其余三个技能正文已读取；未独立核验所有下级参考文件。

本合集没有复制上游全文或 C++ 示例，规则和辅助脚本重新编写。后续如引入上游代码或文档片段，应检查对应版本的许可与署名要求。当前私有使用没有自动授予外部再分发许可。

## 技术文档入口

- [C++ Core Guidelines](https://isocpp.github.io/CppCoreGuidelines/CppCoreGuidelines)：资源、接口、并发与错误处理的进一步参考；实际项目可有领域约束。
- [Clang AddressSanitizer](https://clang.llvm.org/docs/AddressSanitizer.html)
- [Clang ThreadSanitizer](https://clang.llvm.org/docs/ThreadSanitizer.html)
- [clang-tidy](https://clang.llvm.org/extra/clang-tidy/index.html)

工具行为需要与项目安装版本匹配。链接用于查证具体问题，不要求每次技能执行都访问或加载全部文档。
