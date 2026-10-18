# 工具配置与证据

## Sanitizer

- ASan 面向内存越界与 use-after-free 等问题；UBSan 检查启用项目覆盖的未定义行为。支持的目标可使用项目已有的 ASan+UBSan 配置。
- TSan 使用独立构建，不与 ASan 合并。数据竞态检测通过不证明无死锁、协议正确或所有交错安全。
- allocator、未插桩库、共享内存、设备 DMA 和特定同步实现可能有检测盲区；确认实际工具/平台支持。必要时补充合同测试、独立进程或真实设备验证。
- 只在工具链支持时使用相应选项，编译与最终链接均要使用匹配配置。不要直接把主构建目录切成另一种 sanitizer 模式。
- sanitizer 改变运行成本；不拿插桩构建与普通 Release 构建比较性能。
- suppressions 只能针对定位清楚且记录理由的问题；不批量关闭检查来消除失败。

命令应从项目现有脚本或 presets 取得。缺少配置时，先查安装工具的帮助及当前版本官方文档，再选择最小必要的编译/链接选项。

## clang-format / clang-tidy

排版沿用仓库配置和版本；只处理受影响文件或项目要求的范围。诊断优先聚焦当前改动相关的 bugprone、performance、modernize 等具体检查；不要把所有 modernize 建议当作当前任务。

标识符命名检查须映射项目现有约定。命名与 include 风格不由通用 skill 覆盖。

clang-tidy 的编译数据库、宏和生成文件必须匹配目标；分析失败与源代码诊断分开处理。自动修复先看 diff，尤其是跨文件和语言标准相关修改。

## 官方参考

- [Clang AddressSanitizer](https://clang.llvm.org/docs/AddressSanitizer.html)
- [Clang UndefinedBehaviorSanitizer](https://clang.llvm.org/docs/UndefinedBehaviorSanitizer.html)
- [Clang ThreadSanitizer](https://clang.llvm.org/docs/ThreadSanitizer.html)
- [clang-tidy](https://clang.llvm.org/extra/clang-tidy/index.html)

这些链接是查版本行为的入口，不意味着最新文档适用于项目所装版本。
