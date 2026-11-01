# 原始代码案例评审判据

本文件仅供评审者使用。执行者不能读取本文件或之前的评估结论。

## reuse

- 行为：成功、操作失败后均归还已取得的 slot；没有取得 slot 的拒绝路径不能释放他人的占用。
- 复用：先发现并评估项目已有 `ScopeExit`。采用它是符合技能的最小改动；若使用直接控制流，须说明为什么在当前固定路径下更合适。新建另一套 ScopeExit/Lease 框架不符合目标。
- 验证：原失败场景修复后通过，不能删除或弱化行为检查。

## borrow

- 无需修改是合格结果。`ReadWindow` 持有旧快照，`Store::Replace` 不应使已有 view 失效。
- `Read` 的空指针检查区分尚未初始化与合法空字符串，不能当作冗余校验删除。
- 不能用不持有 owner 的 `string_view` 替代 ReadWindow，不能为消除 shared_ptr 引入无关池或锁。
- 结论应定位 owner 与最后访问，不只写“智能指针安全”。

## naming

- 区分返回模式的查询与实际量化动作，以及 stored value 的字节数。
- 修改全部调用方并保持值与返回类型不变；无需旧名兼容转发层，因为输入明确给出全部调用方且允许修改。
- 不要求某个唯一拼写，但应符合项目命名规则且无歧义。验证通过不替代语义判断。

## owner

- 行为：成功与非法头部两条路径都释放区域，`live_regions` 检查保留且通过；区域打开失败时不调用 `CloseRegion`。
- 所有权：用 RAII 绑定释放。`std::unique_ptr<c_api::Region, 删除器 struct>` 是最直接的解法；函数指针删除器（`decltype(&c_api::CloseRegion)`）也能修复泄漏，但不符合技能对删除器 struct 的要求，记为部分满足；手写 owner 时须删除复制、移动操作 `noexcept`、moved-from 状态不会重复释放。只在失败分支补一行 `CloseRegion` 修复了泄漏，但没有建立所有权，不符合技能目标。
- 现代写法：按项目约定改为返回 `std::optional<Header>`，去掉输出参数；不写裸 `new`/`delete`；不使用超出 C++17 的设施（例如 `std::span`）；不修改 `c_region.h`。
- 范围：不新建通用资源框架，不引入异常。

## views

- 行为：三个校验和保持原值；`ParseLimit` 对 `"42"` 成功，对空、非数字、`"42x"`、非正数报告 `kInvalidArgument`，对超出 `int` 的输入报告 `kOutOfRange`。
- 现代写法：`Checksum` 接收 `std::span<const std::byte>` 或 `std::span<const std::uint8_t>`，调用方不再复制（`std::as_bytes`、`subspan` 或字符串的字节视图）；`ParseLimit` 接收 `std::string_view`，用 `std::from_chars`，返回项目的 `Result<int>`；返回值标 `[[nodiscard]]` 可加分但不是必需。
- 约定：沿用 `result.hpp`，不引入 `std::expected`（C++23）或新的错误类型；去掉 `atoi` 和输出参数。
- 验证：`check.cc` 覆盖新的错误区分，不删除原有校验和断言。

## standard-gate

- 标准：以 `-std=c++14` 编译通过，不使用 `std::optional`、`std::string_view`、结构化绑定、`if` 初始化语句、`[[nodiscard]]` 等 C++17 设施，也不建议升级标准。GCC 14 在 C++14 下仍接受 `[[nodiscard]]`，需人工检查或用 clang 编译确认。
- 约定：查找接口返回 `const Entry*`，不存在时为 `nullptr`，与 `FindConfig` 一致；函数为 `const`；用 `map::find`，不用 `operator[]` 意外插入。
- 现代写法仍然适用于 C++14：`auto`、range-for、`std::make_unique`（如需要）、`nullptr`，不写裸 `new`。
- 验证：`check.cc` 覆盖存在与不存在两种情况。

## short-io

- 行为：循环直到写完整条记录；`EINTR` 时重试；其他错误立即返回对应的 `std::error_code`；写入函数返回 0 时报告错误而不是无限循环。
- 写法：用 `span::subspan` 推进剩余数据，不复制记录；保留 `std::error_code` 约定，不引入异常或新的错误类型；返回值可以标 `[[nodiscard]]`。
- 验证：保留原有两个断言，可补充返回 0、多次中断的情况；不修改模拟写函数来让检查通过。

## cmake-module

隐藏检查：`hidden-checks/cmake-module/check.sh`。

- 结构：公开头文件放在 `include/kvstore/storage/`，实现放在 `src/storage/`；公开头文件不 include `checksum/crc32.h`；`kvstore_checksum` 以 `PRIVATE` 链接到 `kvstore_storage`；没有新增 `include_directories`、`link_libraries`、`file(GLOB)` 或对 `CMAKE_CXX_FLAGS` 的修改；新测试注册到 ctest。
- 复用：调用已有的 `kvstore::checksum::Crc32`，不重新实现 CRC。
- 行为（ASan/UBSan）：两条记录正确解析且 `payload` 指向输入本身；空输入返回空列表；头部不足、长度超出剩余数据、长度为 `0xFFFFFFFF` 都返回 `kTruncated` 且不溢出；校验和不符返回 `kCorrupted`；非对齐起点可以解析。
- 写法：长度检查不写成 `offset + length > size`；按字节组装小端整数，不把指针强转为整数指针。

## durable-config

隐藏检查：`hidden-checks/durable-config/check.sh`（替换为记录调用的 `FileSystem` 并注入故障）。

- 原子性：不以写模式打开目标文件；新内容写入同目录的临时文件，写完后 `Sync`，再 `Rename` 到目标；`Rename` 之后打开目录并 `Sync`。
- 失败路径：临时文件 `Sync` 失败、写入时 `ENOSPC` 都返回错误，目标文件保持旧内容，临时文件被删除，所有 fd 都已关闭。
- 复用与约定：只通过 `project::fs::FileSystem` 访问文件，不改接口，不改用 `std::ofstream` 或直接系统调用；保持函数签名与 `std::error_code` 约定。
- 加分：说明 `Sync` 失败后不重试；启动时清理遗留的临时文件或说明这一需求。

## coro-lifetime

隐藏检查：`hidden-checks/coro-lifetime/check.sh`（需要 ASan 可用的 `CXX`）。

- 根源修复：`Store::Put` 中跨越 `co_await` 使用的参数改为按值接收（`std::string key, std::string value`），或以等价方式持有所有权。只在 `WriteBatch` 中把 key 存进容器能通过可见检查，但隐藏检查中“先创建 `Put`、稍后等待”的场景仍会失败，记为不满足。
- 同类问题：`WriteBatch` 自己的引用参数（`tenant`、`items`）同样跨越了惰性启动，应改为按值接收或在说明中证明调用方的存活期。
- 范围：不修改 `async.hpp`，不改成急切启动的任务，不用全局变量或延长调用方变量的寿命来掩盖问题。

## frame-decoder

隐藏检查：`hidden-checks/frame-decoder/check.sh`（ASan/UBSan、单次分配上限 16 MiB、20 秒 libFuzzer）。

- 安全：先检查输入长度再读取头部；声明长度先与 `kMaxPayloadBytes` 比较（返回 `kTooLarge`）再与剩余数据比较（`kTruncated`），不按对端提供的长度分配内存；多余字节返回 `kTrailingBytes`。
- 写法：不再把字节 `reinterpret_cast` 成结构体；按字节组装小端整数，非对齐输入下没有 UBSan 报告；保留 `Result` 约定。
- 测试：补充截断、超长长度、错误魔数、多余字节等回归测试；提供模糊测试入口是加分项。

## abi-review

辅助检查：`hidden-checks/abi-review/check.sh <工作区> <评审文本>`，只用来定位相关段落。

- 必须指出：`Client` 新增成员改变了对象大小与布局，在栈上或作为成员使用 `Client` 的旧二进制会出错；`Observer` 中间插入纯虚函数改变了虚函数表，旧调用方实现的子类缺少该函数，库调用时会跳到错误位置；`Consistency` 的 `kStrong` 从 1 变为 2，旧二进制传入的值含义改变；`DefaultTimeout` 是 `inline`，旧调用方编译进的仍是 500 ms，与库内行为不一致。
- 建议：要么提升 `SOVERSION`（发布 `libkvclient.so.2`），要么按 ABI 兼容方式改写：新成员放进 Pimpl 或保留字段、新虚函数加在末尾并提供默认实现（或使用新接口）、新枚举值追加在末尾、默认超时改为非 `inline` 函数。
- 不误报：新增自由函数 `Version()` 是兼容的新增符号。
- 范围：只报告，不修改代码；区分 ABI 破坏与源码兼容性问题。

## tinyxml-loadfile

隐藏检查：`hidden-checks/tinyxml-loadfile/check.sh`。以工作区根提交（导入的原始代码）为行为基准，在 ASan/UBSan/LSan 下比较 12 个输入，并用 `funopen`/`fopencookie` 构造 seek、tell、读取失败的 `FILE*`。

- 行为：返回值、错误码与文档内容和原始实现一致，包括 CR、CR+LF、孤立 CR 的规范化，调用前流位置不在开头时仍从头读取，空文件报告 `TIXML_ERROR_DOCUMENT_EMPTY`，NULL 文件报告 `TIXML_ERROR_OPENING_FILE`，加载失败前先清空文档。
- 修复：原实现在 `fseek(SEEK_END)` 失败时把当前位置当作文件长度，只解析前缀并返回成功；重构后返回错误或读出完整文档。`ftell` 失败、回到开头失败、短读和读错误都返回错误。
- 项目约束：readme 写明关闭 STL 时不包含任何 STL 文件，也不需要异常和 RTTI，代码按 C++98 编写。不引入 `<vector>`、`<memory>`、`<string>`、`<algorithm>` 等头文件，不使用 `std::unique_ptr`、`nullptr`、`auto`、lambda 或异常；clang `-std=c++98 -pedantic-errors`、GCC libstdc++ `-std=c++98`、`-fno-exceptions -fno-rtti` 都要通过，两种 STL 模式的 `xmltest` 全部通过。
- 写法：缓冲区不再在每条错误路径上手动释放（C++98 写法的不可复制 owner、单一出口或项目已有的 `TiXmlString` 都可以）；取长度和换行规范化可以拆成文件内 `static` 函数；保留说明 XML 规范换行处理的注释要点。
- 范围：只改 `LoadFile`，可在文件内新增辅助函数；不修改其他函数，不改公开接口；在 `tinyxml.h` 中增加私有成员需要说明理由。

## tinyxml-path-lookup

隐藏检查：`hidden-checks/tinyxml-path-lookup/check.sh`（两种 STL 模式，ASan/UBSan/LSan，替换全局 `operator new` 统计查找时的分配）。

- 行为：每层取第一个同名子元素且不回溯；段名整体匹配（`a` 不匹配 `ab`，`roo` 不匹配 `root`）；NULL、空串、开头、末尾或连续的 `/` 返回 NULL；路径从当前节点的子元素开始，不包含当前节点本身；在文本节点上调用返回 NULL；非 const 版本返回同一元素；含冒号的元素名照常匹配。
- 约定：沿用 `FirstChildElement` 的写法，即 const 实现加非 const 的 `const_cast` 转发、Doxygen 注释、返回 `0`；在 `TIXML_USE_STL` 下提供 `std::string` 重载为加分项。
- 项目约束同 `tinyxml-loadfile`。查找时在路径字符串上逐段比较、不分配内存为加分项；切分成 `std::vector<std::string>` 违反关闭 STL 时的约束。
- 测试：用 `xmltest.cpp` 已有的 `XmlTest` 补充测试，两种模式的通过数都增加。
- 范围：只新增代码，不修改已有行。

## lodepng-cpp-wrapper

隐藏检查：`hidden-checks/lodepng-cpp-wrapper/check.sh`。以原始实现为基准比较 21 次调用的结果；测试替换 `lodepng_malloc`/`lodepng_realloc`/`lodepng_free` 和全局 `operator new`，在每个入口的每次分配处依次抛出 `std::bad_alloc`，检查 C 缓冲区和文件描述符是否泄漏。

- 行为：输出参数是追加而不是覆盖；`decode` 只在成功时追加，`compress`/`encode` 在有缓冲区时即使出错也追加（原实现如此）；错误码不变。
- 异常安全：9 个入口在任意一次分配抛出时都不泄漏 `lodepng_malloc` 缓冲区，`load_file` 和经由它的 `decode` 不泄漏打开的文件。
- 项目约束：README 写明 C++ 部分用 `-ansi`（C++98）编译，`lodepng.cpp` 改名为 `.c` 后可按 C89 编译。不使用 `std::unique_ptr`、lambda、`nullptr` 或移动语义；libc++ 在 C++98 模式下仍提供 `std::unique_ptr`，所以用 GCC libstdc++ 检查。新代码留在 `LODEPNG_COMPILE_CPP` 区段内；`LODEPNG_NO_COMPILE_*` 的各种组合都不能新增警告，例如只在部分配置下使用的 `static` 辅助函数会触发 `-Wunused-function`。
- 写法：缓冲区交接只写一处（不可复制 owner 的析构函数或成员函数），`lodepng_free` 和 `insert` 不再逐个函数重复；不修改 `lodepng.h` 和 C 部分。
- 加分：指出 vector 重载 `decode` 中 `(unsigned)in.size()` 的截断等相邻问题，并说明不在本任务中修改；直接修改也可以接受，但要在说明中写出。

## tinyxml2-strict-numbers

隐藏检查：`hidden-checks/tinyxml2-strict-numbers/check.sh`。int、unsigned、bool、double、float 五组转换分别经属性、`XMLAttribute` 和文本三个入口测试，在 ASan/UBSan/LSan 下共 136 个用例；`"2.0"` 只记录结果。

- 行为：整组修复，不只是题目点名的 int 和 unsigned。失败时返回原来的错误码，不写输出参数；`"010"` 按十进制读成 10（不能用 base 0）；unsigned 拒绝负号和超过 `UINT_MAX` 的值；float 超出 `FLT_MAX` 时报错。
- 已有合同：`xmltest.cpp` 的 “Query attribute: double as int” 要求 `"2.0"` 按整数读成 2。题目“整个值必须是合法的十进制数”对整数类型可以理解为拒绝它，所以保留或拒绝都可以；拒绝时修改的只能是这条断言，并且必须在说明中指出改变了已有测试的合同。没有说明记为不满足。
- 项目约束：readme 写明不依赖异常、RTTI 和 STL，代码按 C++98 编写，所以不能用 `std::from_chars`、`std::stoi`、`std::istringstream`、`long long`/`strtoll` 或 `nullptr`。clang `-std=c++98 -pedantic-errors`、GCC libstdc++ 和 `-fno-exceptions -fno-rtti` 都不能新增诊断；`<cerrno>`、`<cfloat>` 等 C 兼容头文件可以使用，沿用文件中 Android 分支的写法为加分项。
- 范围：只改 `XMLUtil::To*`，可以新增文件内辅助函数；`xmltest.cpp` 只新增测试，不改已有行，也不把 CRLF 换成 LF。
- 写法：跳过空白和“已读完”的判断复用 `XMLUtil::SkipWhiteSpace`，校验逻辑只写一处；`ToFloat` 复用 `ToDouble` 再检查范围为加分项。

## inih-parse-string

隐藏检查：`hidden-checks/inih-parse-string/check.sh`。在 6 种编译选项下比较 37 个输入的回调序列和返回值，输入包括仓库自带的测试文件、空串、无结尾换行、CRLF、单独的 CR、BOM、续行、注释、用户错误和接近 `INI_MAX_LINE` 的长行；还用原始单元测试对照原基线，并检查三种按文件名构造 `INIReader` 的写法。

- 行为：`ini_parse_string` 按 `fgets` 的语义切行：每次最多读 `INI_MAX_LINE - 1` 字节并保留换行，长行剩下的部分作为下一行；先按 `'\n'` 切分再截断与文件解析结果不同。不修改输入字符串；`INI_USE_STACK=0` 时不泄漏。
- 复用：解析循环只保留一份，抽成以读取函数为参数的内部函数或等价结构；复制整个循环不符合要求。借助 `tmpfile`、`fmemopen` 等方式经由 `FILE*` 解析，在没有文件系统的嵌入式环境中不可用，记为不满足。
- 项目约束：`ini.c` 是 C 代码，保持文件已有的 C89 写法（`/* */` 注释、声明在块首）；`ini.h` 的 `extern "C"` 覆盖新声明，新声明带有与相邻函数一致的注释。
- C++ 封装：新的构造方式不能截获已有的按文件名构造。只加 `INIReader(const char*)` 会让 `INIReader("file.ini")` 把文件名当作 INI 内容解析；`INIReader(const char* buffer, size_t size)`、带标记类型的构造函数或静态工厂都可以。保持 INIReader 已有的 C++98 写法。
- 测试：在 `tests/unittest.c`（同时扩展基线）或 C++ 示例中覆盖 `ini_parse_string`；扩展基线时保留文件原有的换行风格。
- 范围：不修改 `rstrip`、`lskip` 等无关函数，不改写 `ini.h` 中已有的声明。

## stb-write-errors

隐藏检查：`hidden-checks/stb-write-errors/check.sh`。用 `funopen`/`fopencookie` 构造的 `FILE*` 对 png、bmp、tga（RLE 与非 RLE）、hdr、jpg 的文件入口分别注入 `fopen` 失败、全部写入失败、写到一半失败、只有最后一个字节失败和 `fclose` 失败，在 ASan/UBSan/LSan 下运行；成功时的输出与原始实现逐字节比较。

- 行为：头文件说明“Each function returns 0 on failure”覆盖全部文件入口，题目点名的 `stbi_write_png` 只是例子。bmp、tga、hdr、jpg 经 `stbi__start_write_file`/`stbi__end_write_file` 共用写文件路径，同样要报告失败；缓冲区里的最后一段数据在 `fclose` 时才写出，所以必须检查 `fclose` 的返回值，只看 `fwrite` 或 `ferror` 不够。失败时 `FILE` 恰好关闭一次，PNG 缓冲区不泄漏。
- 不能扩大：`stbi_write_func` 回调没有返回值，`*_to_func` 无法得知写入失败，保持原样；修改回调类型或已有公开声明会破坏所有调用方，记为不满足。新增公开接口不是任务要求。
- 项目约束：同一份代码按 C99 `-pedantic`、`STBI_WRITE_NO_STDIO`、`STB_IMAGE_WRITE_STATIC`、clang 与 GCC 的 C++98 编译都不能新增诊断；声明放在块首，与文件其余部分一致。
- 范围与写法：只改 stdio 写文件的辅助函数、写上下文和五个文件入口，不改编码器。参考修复约 15 行：`stbi__end_write_file` 返回 `!ferror(f)` 与 `fclose` 的结果，四个入口据此返回 0，PNG 检查 `fwrite` 和 `fclose`。
- 报告：说明合同覆盖了哪些入口。

## minini-number-defaults

隐藏检查：`hidden-checks/minini-number-defaults/check.sh`。`ini_getl` 与 `ini_getf` 分别在独立进程中检查合法值、非法值和越界值（ASan/UBSan/LSan），C++ 的 `minIni::geti` 检查 int 范围；`ini_getbool`、`ini_gets`、枚举、浏览和写入接口的输出与原始实现逐字节比较。

- 行为：`DefValue` 的合同对 `ini_getl`、`ini_getf` 和 C++ 包装一致适用，题目点名的 `ini_getl` 只是例子。整个值（允许前后空白，包括引号内的空白）必须是目标类型的数：`ini_getl` 拒绝 `"12abc"`、`"1.5"`、`"0x"`、`"0x1G"`、溢出；`"010"` 读成 10；`" 0x1F "` 读成 31。`ini_getf`（默认 `INI_REAL` 为 float）拒绝 `"1.5x"`、`"1,5"`、超出 float 范围的值。`minIni::geti` 在超出 int 范围时返回 `DefValue`，不截断；`wxMinIni.h` 的同名函数一并处理为加分项。`"+5"`、`"-0x10"`、`"nan"`、`".5"` 等只记录结果。
- 不能扩大：`ini_getbool` 的文档规定只看首字符（`"1abc"` 为真），保持原样；`ini_gets` 和写入接口不变。
- 已有合同：手册（`doc/minIni.pdf`）写的是 `DefValue` 只在 key 不存在时返回，修复改变了文档描述，说明中应指出（软判据）。
- 项目约束：README 说明不使用动态内存，`minIni.c` 保持 C89，在 `INI_READONLY`、`INI_ANSIONLY`、`NDEBUG`/`INI_NOBROWSE`/`PORTABLE_STRNICMP` 和没有 `INI_REAL` 的 glue 下都不新增诊断，仍能按 C++ 编译；新代码使用 `_tcstol`、`_tcstod`、`_totupper` 等 TCHAR 映射，不直接调用只接受 `char` 的函数；`ini_getf` 仍经 glue 的 `ini_atof` 转换为加分项。`minIni.h` 的 C++ 类保持 C++98。源文件使用 CRLF，不转换换行。
- 测试：在 `dev/test.c` 或 `dev/test2.cc` 中覆盖数值读取，测试结束后 `test.ini` 恢复原样。

## fmt-optional-formatter

隐藏检查：`hidden-checks/fmt-optional-formatter/check.sh`。基本输出、格式说明符、字符串与字符、嵌套与 ranges、`wchar_t`、约束六组各自编译成独立程序，在 C++17 和 C++20 下运行；`variant`、`monostate`、`thread::id` 的输出与原始实现比较。

- 行为：有值输出 `optional(<值>)`，空值输出 `none`；`{:x}`、`{:>4}`、`{:.2f}` 作用于内部的值；字符串和字符加引号并转义；`optional<optional<int>>`、`optional<vector<int>>`、`vector<optional<int>>` 正确嵌套；`fmt::is_formattable<std::optional<NotFormattable>>` 为假。
- 复用与陷阱：照抄相邻的 `variant` 格式化器会用 `detail::write<Char>(out, "variant(")` 写窄字符串，这在 `wchar_t` 下编译不过（原始 `variant` 本身也有这个问题），也无法应用格式说明符。`ranges.h` 已有 `detail::string_literal` 和 `maybe_set_debug_format` 的写法，复用它们能同时满足字符类型和调试格式；直接复用 `write_variant_alternative` 或 `write_escaped_string` 也算复用。
- 泛型：一个 `formatter<std::optional<T>, Char, enable_if_t<is_formattable<T, Char>::value>>` 特化就够了，持有 `formatter<T, Char>` 并把解析委托给它；为唯一的 `std::optional` 新建 `is_optional_like` 一类的 trait 或通用包装基类属于过度设计，在 `style.py` 的新增类型与行数中体现。
- 项目约束：fmt 支持 C++11，`<optional>` 只在 C++17 且可包含时引入，用 `__cpp_lib_optional` 保护；C++11/14/17/20 下 clang 与 GCC 都不新增诊断，实例化时不产生警告。
- 测试与文档：`test/std-test.cc` 覆盖 `std::optional`；`doc/api.rst` 列出 `std.h` 支持的类型，更新它为加分项。

## httplib-header-injection

隐藏检查：`hidden-checks/httplib-header-injection/check.sh`。用原始 TCP 监听记录客户端实际发出的字节，检查 11 个入口：`Post`、`Put`、`Patch`、`Delete` 的 `content_type`，内容提供者形式的 `Post`，`Headers` 参数的值、名称和只含 LF 的值，带 `Headers` 的 `Post`，`set_default_headers`，`set_bearer_token_auth`；另有 3 个必须原样发送的对照（正常的 Content-Type、含冒号和制表符的值、UTF-8 值）。

- 行为：题目点名的是 `Post` 的 `content_type`，合同是“客户端发出的请求中不能出现含 CR/LF 的头部”，所以调用方传入的 `Headers`、默认头和 bearer token 都在范围内。上游 0.12.4 的修复把 `headers.emplace` 换成 `set_header`，只覆盖 `content_type` 路径，在这里不满足；在 `write_request` 写出头部前统一过滤可以一次覆盖所有入口。头部直接丢弃，请求照常发送；让整个请求失败或抛异常不满足。
- 复用：项目已有 `detail::has_crlf` 和 `Request::set_header` 的同样语义，重新手写 CR/LF 判断记为软判据不满足。
- 不能扩大：不改已有函数签名，不拒绝冒号、制表符或非 ASCII 的合法值。
- 项目约束：C++11，测试 Makefile 的 `-Wall -Wextra -Wtype-limits -Wconversion -Wshadow` 与 `-fno-exceptions -DCPPHTTPLIB_NO_EXCEPTIONS` 下 clang 和 GCC 都不新增诊断；`ServerTest` 离线套件仍然通过。
- 测试与报告：`test/test.cc` 覆盖头部注入。在序列化处统一过滤时，说明不必逐个列出入口，所以报告提到哪些入口只记录、不评分。移动已有的 `detail::has_crlf` 使其在 `write_headers` 之前定义属于复用。

## cxxopts-duration-values

隐藏检查：`hidden-checks/cxxopts-duration-values/check.sh`。单位换算、精确性、范围、浮点计数、语法、用法、`std::optional` 七组各自编译成独立程序，在 ASan/UBSan 下运行；前六组用 C++11，`std::optional` 用 C++17，单位、范围和语法三组另用 `CXXOPTS_NO_REGEX` 运行一次。

- 行为：六个单位换算到任意 `std::chrono::duration`，包括 `std::ratio<1, 30>` 这样的非标准周期；整数计数时 `1500ms` 读成 `seconds`、`90s` 读成 `minutes` 要报错，`32s` 读成 `duration<short, milli>` 可以而 `33s` 不行，`-1s` 读成无符号计数报错，换算溢出不能是未定义行为，超过 2^53 的计数保持精确（经 `double` 或 `long double` 换算会丢掉低位，macOS arm64 上两者相同）；浮点计数接受 `1.5s`。缺少或未知的单位、`1h30m` 一类组合写法都报错，且异常类型与其他无法解析的值相同（`incorrect_argument_type`）。
- 范围：题目只给了 `value<milliseconds>()` 和命令行写法，合同是“像 `int`、`double` 一样作为选项值类型”，所以 `default_value`、`implicit_value`、`std::vector<duration>`、位置参数、`KeyValue::as` 和 C++17 的 `std::optional<duration>` 都在范围内。它们都通过未限定的 `parse_value` 调用，而时长类型的关联命名空间不含 `cxxopts::values`，新重载必须声明在 `vector` 与 `optional` 重载之前；放在后面时单值用法正常、容器用法编译不过。
- 复用：计数用已有的 `parse_value(text, Rep&)` 读取，同时得到整数解析的符号、十六进制、范围检查和浮点解析；用 `std::stoll`、`strtol`、正则或字符串流重写（包括为浮点计数另写更严格的流解析）记为软判据不满足，而且 `try`/`catch` 会让 `CXXOPTS_NO_EXCEPTIONS`（`-fno-exceptions`）构建失败。错误通过 `throw_or_mimic<exceptions::incorrect_argument_type>` 报告。
- 泛型：一个 `duration<Rep, Period>` 的重载比 `!is_integral` 的兜底模板更特化，不需要 `is_duration` 一类的 trait 或新的 SFINAE 门；C++11 下整数与浮点计数的换算可以用项目已有的 `std::true_type`/`std::false_type` 标签分派（同 `checked_negate`）。新增类型 trait 记为软判据不满足；模板、结构体、标签分派、表和 lambda 的数量只记录，用于比较各组。
- 项目约束：C++11，clang 与 GCC 在 C++11/14/17/20 下按项目的警告选项（`-Wconversion`、`-Weffc++` 等）不新增诊断；标准 typedef 与 `duration<double>` 的实例化不能产生警告，`short`、32 位、无符号、`float` 计数的实例化警告只记为软判据。`options_test` 在 C++11 与 C++17 下通过，原始 `options.cpp` 配新头文件也通过。
- 已知的上游问题：`integer_parser` 对每个负数都调用 `std::abs(std::numeric_limits<T>::min())`，64 位计数时是未定义行为，所以负数用例使用 32 位计数。`milliseconds` 等标准时长的计数是 64 位，修复这处是为本题服务，`integer_parser` 内的改动只记录、不计入“头文件只新增代码”；把所有整数计数都按 64 位读取会触发这处未定义行为，算作实现问题。
- 测试与文档：`test/options.cpp` 覆盖时长且只新增；README 列出支持的值类型，补充时长为加分项。

## 记录方法

在仓库外记录每次执行的模型/宿主、skill 与输入快照、原始提示、修改及命令结果，不提交运行报告或产物。分别标注行为、复用、保持不变量、范围控制和证据是否满足。

同一模型的一次成功只能算一次 smoke。规则修改后使用新的同类输入复测，不把已泄露判据的重复运行计作独立评估。

第五轮起，`hidden-checks/common/style.py` 对非测试源码统计新增行数、新增函数和新增判空检查，并列出过长的新名称；新名称带 `ensure`、`try`、`maybe`、`safe`、`checked`、`validate`、`do`、`handle`、`process` 前缀记为软判据不满足。原始仓库中已经出现的名称视为沿用项目命名，不计入新名称。行数和函数数只用于比较各组，不单独判定好坏。
