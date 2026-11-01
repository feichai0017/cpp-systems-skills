# 原始代码案例

第一、二轮的案例代码是为本合集编写的小项目，第三轮起从固定版本的开源仓库导入。前两轮各案例的 C++ 标准写在其 `AGENTS.md` 中：`standard-gate` 为 C++14，`owner`、`reuse`、`borrow`、`naming` 为 C++17，其余为 C++20。

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

## 第三轮：真实遗留仓库

前两轮的案例是为技能编写的小项目，强模型不用技能也能完成。第三轮在固定版本的真实仓库上重构或新增功能；这些仓库有自己的年代和可移植性约定（C++98、可关闭 STL、可按 C89 编译、不依赖异常），技能的现代写法要服从项目约定，判断改动范围、保持已有行为都是评审重点。

| 案例 | 来源 | 任务 | 隐藏检查 |
| --- | --- | --- | --- |
| `tinyxml-loadfile` | TinyXML 2.6.2 | [重构](tinyxml-loadfile/TASK.md) `TiXmlDocument::LoadFile(FILE*)` | 与原始实现比较 12 个输入；seek/tell/读取失败的 `FILE*`；C++98、关闭 STL、无异常构建 |
| `tinyxml-path-lookup` | TinyXML 2.6.2 | [新增](tinyxml-path-lookup/TASK.md) `FirstChildElementByPath` | 段名整体匹配与不回溯；项目约定的重载和注释；查找时的分配次数 |
| `lodepng-cpp-wrapper` | lodepng `e584a84` | [重构](lodepng-cpp-wrapper/TASK.md) C++ 封装的重复与异常安全 | 与原始实现比较 21 次调用；逐次注入 `std::bad_alloc`；各 `LODEPNG_NO_COMPILE_*` 配置的警告；C89 构建 |

- `setup.sh` 按固定 URL 下载源码并校验 SHA-256，导入为工作区的根提交；把 `CPP_EVAL_SOURCES` 设为存放归档的目录可以离线运行。隐藏检查以根提交为行为基准，并把构建和测试产物写入 `.git/info/exclude`。
- 检查 C++98 下的库用法需要 GCC（libstdc++）；找不到时这一项记为 SKIP，可以用 `GXX` 指定。
- jsoncpp 0.7.0 的 CMake 依赖已在 CMake 4 中移除的 `FindPythonInterp`，暂未收入。

## 第四轮：技能修改后的复测

第三轮中技能组有一次在关闭 STL 的 TinyXML 中引入 `std::vector`，两组都没有补齐同类接口的重载，对照组有两次改写了任务之外的已有行。`cpp-core` 据此补充了库范围与移植约束、同类接口的整组写法和不改动无关行的规则。按记录方法，复测使用新的同类仓库，不重复已经暴露判据的案例。

| 案例 | 来源 | 任务 | 隐藏检查 |
| --- | --- | --- | --- |
| `tinyxml2-strict-numbers` | TinyXML-2 2.2.0 | [修复](tinyxml2-strict-numbers/TASK.md)把 `"12abc"` 读成 12 的数值转换 | 五组转换、三个入口共 136 个用例；已有测试中 `"2.0"` 合同的改变须在说明中写明；C++98、无 STL、无异常；`xmltest.cpp`（CRLF）只新增不改动 |
| `inih-parse-string` | inih r30 | [新增](inih-parse-string/TASK.md) `ini_parse_string` 与 `INIReader` 的字符串构造 | 6 种编译选项下与 `ini_parse_file` 逐个回调比较；C89 写法；解析循环不复制；按文件名构造不被新重载截获 |

## 第五轮：合同范围、过度工程与命名

第四轮中技能组有 4/6 次只修了题目点名的 `ToInt`/`ToUnsigned`，两组在 high 强度下都没有说明改变了已有测试的合同。`cpp-core` 据此补充了按行为合同确定范围、报告已有合同的变化，以及不重复检查、单一路径不做多层抽象、不用防御式前缀和重复上下文命名的规则。复测加入第三轮时的技能版本（`--skills-rev 9bce81b`），区分新规则和技能原有倾向的影响。

| 案例 | 来源 | 任务 | 隐藏检查 |
| --- | --- | --- | --- |
| `stb-write-errors` | stb `003501f`（stb_image_write v1.16） | [修复](stb-write-errors/TASK.md)写文件失败时 `stbi_write_png` 仍返回 1 | 五个文件入口 × 五种写入故障；`fclose` 失败；回调类型和公开声明不变；与原始输出逐字节比较；C/C++98 与配置宏的诊断 |
| `minini-number-defaults` | minIni `1bb6557` | [修复](minini-number-defaults/TASK.md)`ini_getl` 把 `"abc"` 读成 0 | `ini_getl`、`ini_getf`、`minIni::geti` 的整值与范围；`ini_getbool` 等接口输出不变；C89、无动态内存、TCHAR 映射、CRLF |

- 两个案例都有题目点名之外、承担同一合同的入口，也有看起来相似但合同不同、必须保持不变的接口（stb 的回调变体、minIni 的 `ini_getbool`）。
- `tinyxml2-strict-numbers` 再用当前技能和 `9bce81b` 各运行一组，与第四轮已有结果比较；这组用过的案例只作对照，不计为独立复测。

## 第六轮：复杂的现代 C++ 仓库

前几轮的仓库以 C 和 C++98 为主。第六轮换成模板较重的 {fmt} 和单头文件网络库 cpp-httplib，检验同族入口、复用已有机制和泛型写法；技能组使用加入“先复用、不处理不会出现的情况、泛型与模板元编程”之后的版本，并与第五轮的技能版本（`--skills-rev 8d73c2e`）和无技能组比较。

| 案例 | 来源 | 任务 | 隐藏检查 |
| --- | --- | --- | --- |
| `fmt-optional-formatter` | {fmt} 9.1.0 | [新增](fmt-optional-formatter/TASK.md) `std::optional` 的格式化 | 六组行为在 C++17/20 下分别编译；`wchar_t` 与约束；C++11–20 的诊断；已有格式化器输出不变 |
| `httplib-header-injection` | cpp-httplib 0.12.3 | [修复](httplib-header-injection/TASK.md) `content_type` 的 CRLF 注入（CVE-2023-26130） | 在线路上检查 11 个客户端入口和 3 个对照；离线 `ServerTest` 套件；C++11 与无异常构建的诊断 |

- fmt 中相邻的 `variant` 格式化器本身在 `wchar_t` 下编译不过，照抄它会把问题带进新代码；`ranges.h` 已有正确的写法。
- httplib 上游 0.12.4 的修复只覆盖 `content_type` 路径，按题目的合同，调用方传入的头部也在范围内。

## 第七轮：没有现成答案的泛型任务与封装层复测

第六轮的 fmt 任务在上游 fmt 10 中有现成实现，三组都接近满分；`cpp-core` 的命名规则还让一次运行改名了 fmt 自己的 `maybe_set_debug_format`。第七轮选用上游从未实现的功能，检验泛型写法和复用；同时用修改后的技能复测第五轮 `minIni::geti` 无人处理的封装层。

| 案例 | 来源 | 任务 | 隐藏检查 |
| --- | --- | --- | --- |
| `cxxopts-duration-values` | cxxopts 3.3.1 | [新增](cxxopts-duration-values/TASK.md) `std::chrono::duration` 选项值 | 七组行为在 ASan/UBSan 下分别编译，含无正则实现；任意周期、精确性与溢出；容器与 `optional` 的两阶段查找；C++11–20 与项目警告选项的诊断；无异常构建；复用与 trait |
| `minini-number-defaults` | minIni `1bb6557` | 第五轮的同一案例 | 同第五轮 |

- cxxopts 的 `checked_negate` 本身带有 `checked` 前缀，用于观察修改后的命名规则是否只约束新名字。
- `minini-number-defaults` 是封装层规则的来源，复测只说明规则在原案例上是否生效，不计为独立证据；对照沿用第五轮同一 Codex 版本的结果，另加入第六轮的技能版本（`--skills-rev a28f6a3`），区分封装层这句与复用、泛型规则的影响。

## 第八轮：标准库复用、已有解析的接受范围与文档

第七轮中 18 次 cxxopts 运行有 13 次手写最大公约数，而不在单位分派处用 `std::ratio_divide`；高强度下多数运行为浮点计数另写了更严格的解析，3 次改动了共用的 `stringstream_parser`；README 两轮共 36 次都没有更新；`minIni::geti` 的窄化只在 1/6 次被处理。`cpp-core` 据此补充了标准库复用、沿用已有解析的接受范围、同步文档和包装层窄化的规则，`generic-programming.md` 补充了“运行时只分派一次、换算交给编译期”的写法。

| 案例 | 来源 | 任务 | 隐藏检查 |
| --- | --- | --- | --- |
| `args-duration-values` | args 6.6.1 | [新增](args-duration-values/TASK.md) `std::chrono::duration` 参数值 | 七组行为（含 `ARGS_NOEXCEPT`）在 ASan/UBSan 下分别编译；计数写法与 `Rep` 一致（空白、`+`、十六进制、八进制）；项目警告选项与 CMake 测试；复用、手写最大公约数、trait 与 README |
| `cxxopts-duration-values` | cxxopts 3.3.1 | 第七轮的同一案例 | 同第七轮，另记录手写最大公约数 |
| `minini-number-defaults` | minIni `1bb6557` | 第五轮的同一案例 | 同第五轮 |

- `args-duration-values` 与第七轮是同一类任务、不同的代码结构，用于检验新规则能否迁移到新仓库；技能组与第七轮的技能版本（`--skills-rev 3f9cb1a`）和无技能组比较。
- 后两个案例是新规则的来源，只运行新技能组，与之前各轮同一 Codex 版本的结果比较，不计为独立证据。

## 第九轮：标准库的限制、多编译器与隔离运行

第八轮中至少 5 次高强度运行先用了 `std::ratio_divide`，又因“极端自定义周期会在编译期溢出”改成运行时约分和手写最大公约数；`generic-programming.md` 在低强度下 0/6 次被读取；一次运行的头文件 GCC 编译不过。`cpp-core` 据此在正文写明“运行时只分派一次”，并把标准库设施自身的限制视为可接受的边界；交付检查要求至少用两种编译器编译。运行脚本从本轮起给每次运行临时的 `HOME` 和 `CODEX_HOME`，用户的记忆、个人技能和配置不再进入任何一组。

| 案例 | 来源 | 任务 | 隐藏检查 |
| --- | --- | --- | --- |
| `yaml-duration-values` | yaml-cpp 0.9.0 | [新增](yaml-duration-values/TASK.md) 从节点读取 `std::chrono::duration` | 七组行为链接 ASan/UBSan 构建的库；计数写法与 `convert<Rep>` 一致；clang 与 GCC 的头文件诊断和实例化；项目测试；复用、手写最大公约数、trait 与 `docs/Tutorial.md` |
| `args-duration-values` | args 6.6.1 | 第八轮的同一案例 | 同第八轮 |

- `yaml-duration-values` 的技能组与第八轮的技能版本（`--skills-rev 4969905`）和无技能组比较。
- `args-duration-values` 是新规则的来源，只运行新技能组和无技能组；与第八轮比较时注意第八轮没有隔离运行环境。

## 第十轮：冗余检查

第九轮起改用 `gpt-6-astra`。几道时长题都很少诱发冗余检查，两组没有差别；这一轮单独用一个合同写明前提的题目检验冗余检查。

| 案例 | 来源 | 任务 | 隐藏检查 |
| --- | --- | --- | --- |
| `jsmn-find-key` | jsmn `25647e6` | [新增](jsmn-find-key/TASK.md) `jsmn_find` | 29 个用例 × 四种配置与 C++，令牌数组恰好 `count` 个；按合同分类的冗余检查；分配、第二条路径与额外接口；`JSMN_HEADER`/`JSMN_STATIC`；C89、C99、C++11 下 clang 与 GCC 的诊断 |
| `jsmn-find-key-implicit` | jsmn `25647e6` | [同一题](jsmn-find-key-implicit/TASK.md)，不写调用方保证 | 同 `jsmn-find-key`；判空与越界检查不符合项目约定 |

- 题目写明调用方保证 `js`、`tokens` 来自同一次成功解析，`count` 是返回值，`0 <= object < count`，`key` 以 NUL 结尾；对这些条件的检查都算冗余。键后面没有值是 jsmn 实际会产生的情况，对它的检查是合同需要的。
- 技能组与无技能组在 high 和 low 下各运行 5 次。
- `jsmn-find-key-implicit` 是同一题去掉“调用方保证”一段的变体，检查相同，用于观察合同不写前提时的默认防御检查。

## 运行与记录

`scripts/run_codex_eval.py` 为单个案例准备隔离工作区并运行 Codex：

```sh
python3 scripts/run_codex_eval.py durable-config --arm skills --trial 1 \
  --out /tmp/cpp-skill-evals --effort high --cxx /opt/homebrew/opt/llvm/bin/clang++ --grade
```

- 每次运行使用临时的 `HOME` 和 `CODEX_HOME`，只复制登录信息和模型设置；`--shared-home` 改用用户自己的目录（第八轮及以前都是这样运行的）。
- `--arm skills` 把技能（默认全部）复制到工作区的 `.agents/skills`，并写入 `.git/info/exclude`，不进入评审的 diff；`--arm control` 不安装技能。`--skills-rev <提交>` 安装该提交中的技能，运行目录名记为 `skills@<提交>`。
- 输出目录必须在仓库外。每次运行保存事件日志、最终回复、diff、`run.json`（Codex 版本、技能提交、读取过的技能文件等）和可选的 `grade.txt`。
- 需要判断技能带来的提升时，同一模型、同一设置下有无技能各运行多次，按次数报告每项判据的满足情况；少量运行只说明观察到的差异，不写成统计结论。

这些案例用于发现行为问题。运行产物、成绩和报告保存在仓库外，本目录只维护原始案例。
