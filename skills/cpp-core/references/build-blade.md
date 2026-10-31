# Blade：BUILD 文件、依赖与配置

修改或新建 Blade 项目时阅读。以下内容依据 [blade-build](https://github.com/chen3feng/blade-build) 固定提交 `b95bff3e4e35c3b53265c7522e42e1aedf84f3f8` 的英文文档（核对日期 2026-10-31）；项目安装的 Blade 版本较旧时，以其自带文档和 `blade <subcommand> --help` 为准。项目已有的 BUILD 风格、目录结构和第三方库组织优先。

## 工作区与目标

- 工作区根目录有 `BLADE_ROOT`，它同时是项目级配置文件；个人临时调整放在不提交的 `BLADE_ROOT.local`。
- 每个目录一个 `BUILD` 文件。目标名与路径共同组成唯一标识：`//storage/segment:segment`。
- include 路径从工作区根目录写起：`#include "storage/segment/segment.h"`，不靠 `incs` 添加搜索路径。

```python
cc_library(
    name = 'segment',
    hdrs = [
        'segment.h',
    ],
    srcs = [
        'segment.cc',
        'segment_index.h',     # 私有头文件放在 srcs
    ],
    deps = [
        ':segment_format',
        '//common/base:status',
        '#pthread',
    ],
    visibility = ['//storage/...', '//service/...'],
)

cc_test(
    name = 'segment_test',
    srcs = ['segment_test.cc'],
    deps = [':segment'],
    testdata = ['testdata/small.seg'],
)

cc_binary(
    name = 'segment_tool',
    srcs = ['segment_tool.cc'],
    deps = [':segment'],
)
```

BUILD 风格：4 空格缩进、单引号、目标名小写、`srcs` 按字母排序；`deps` 先写本目录的 `:name`，再按字母顺序写其他目录的 `//dir:name`；每行一个参数时最后一项也带逗号；目标之间空一行。

## 依赖写法

| 写法 | 含义 |
| --- | --- |
| `':name'` | 同一个 BUILD 文件中的目标 |
| `'//path/to/dir:name'` | 其他目录的目标，路径从 `BLADE_ROOT` 起算 |
| `'#pthread'`、`'#z'` | 系统库，相当于 `-lpthread`，会传递给依赖本目标的目标 |
| `'vcpkg#fmt:fmt'` | vcpkg 管理的库，需要先在 `BLADE_ROOT` 的 `vcpkg_config` 中声明 |

`deps` 只写本目标直接用到的库：源文件或公开头文件 include 了哪个库的头文件，就依赖那个库。不依赖“下游碰巧也链接了”的间接依赖。

## 头文件依赖检查

- 普通 `cc_library` 必须声明 `hdrs`，只列公开头文件；确实没有公开头文件时显式写 `hdrs = []`。私有头文件放在 `srcs`。
- 纯头文件库也要用 `cc_library` 描述，列出 `hdrs` 和它的直接依赖。否则缺失的依赖要到最终使用者链接时才暴露，很难定位。
- 一个目标 include 某个头文件时，该头文件所属的 `cc_library` 必须在它的 `deps` 中，否则 Blade 报 missing dependency。按报错补依赖之前，先确认这个头文件确实应该被直接使用；如果补依赖会违反 visibility，说明应该依赖一个对外暴露的库，而不是绕过可见性。
- Blade 也检查未使用的依赖（默认 warning）。`keep_deps` 只在依赖确实不能被 include 关系识别时使用。
- 库粒度过大时，`hdrs` 检查会带入不必要的依赖；按职责拆分库，例如把只含声明的 `foo_prod.h` 单独成库。

严重程度在 `BLADE_ROOT` 中配置：

```python
cc_config(
    cxxflags = ['-std=c++20'],
    hdr_dep_missing_severity = 'error',
    unused_deps_severity = 'warning',
)

cc_library_config(
    hdrs_missing_severity = 'error',
)
```

存量项目可以用 `hdr_dep_missing_suppress`、`hdrs_missing_suppress`、`unused_deps_suppress` 记录已有问题，新代码不新增例外。

## 可见性

Blade 2 起目标默认私有，同一目录内的目标总是互相可见。

```python
visibility = []                    # 只对本 BUILD 文件可见
visibility = ['PUBLIC']            # 对所有目标可见
visibility = ['//module:*']        # module 目录下的目标，不含子目录
visibility = ['//module:...']      # module 目录及所有子目录
```

只把稳定的接口库设为对外可见；实现细节库保持私有，由同目录的接口库依赖。存量项目可以用 `global_config(legacy_public_targets = [...])` 保持旧目标公开，新目标显式声明可见性。

## 编译选项与配置

| 位置 | 用途 |
| --- | --- |
| `cc_config(cxxflags = [...])` | 全局 C++ 标准等语言选项，例如 `'-std=c++20'` |
| `cc_config(warnings / cxx_warnings = [...])` | 全局警告，默认 `['-Wall', '-Wextra']` |
| `cc_config(optimize = ['-O2'])` | 优化选项，debug 构建时自动关闭 |
| 目标的 `extra_cxxflags` | 只对该目标的 C++ 源文件生效的选项，尽量少用 |
| 目标的 `defs` | 预处理宏 |
| 目标的 `optimize`、`always_optimize` | 目标级优化；成熟且性能敏感的库（哈希、压缩）可以始终优化 |
| `warning = 'no'` | 关闭该目标的全部警告，只用于不可修改的第三方代码 |

项目级选项改在 `BLADE_ROOT`，不在各个 BUILD 里重复 `-std=`。查看最终生效的配置：`blade dump --config`。

## 第三方库

- 系统库用 `#name`。
- vcpkg：在 `BLADE_ROOT` 中声明允许使用的包并固定 baseline，目标中写 `vcpkg#<port>:<lib>`：

```python
vcpkg_config(
    baseline = '2024-12-15',
    packages = {
        'fmt': '10.2.1',
    },
)
```

- 预编译库用 `prebuilt_cc_library`，通常放在 `thirdparty/<name>/BUILD` 中统一管理；需要从源码构建的外部项目（autotools、CMake）用 `foreign_cc_library` 描述其安装结果。
- 源码 vendor 进仓库的第三方库，用 `cc_library` 描述，并可设置 `system_include = True`，让它的头文件按系统头文件处理，避免第三方警告进入本项目的 `-Werror`。
- gtest 在 `BLADE_ROOT` 中通过 `cc_test_config(gtest_libs = '...', gtest_main_libs = '...')` 指定，`cc_test` 自动链接，不需要在每个测试的 `deps` 中写 gtest。

## 生成代码与特殊链接

- protobuf 用 `proto_library`，C++ 代码总会生成；include 时写从工作区根目录起的全路径，把 `.proto` 换成 `.pb.h`，例如 `"common/rpc/meta.pb.h"`，并依赖对应的 `proto_library`。
- 依赖全局对象构造来自注册（工厂注册、插件注册）的库设 `link_all_symbols = True`，并把注册代码拆成单独的小库，避免整个大库被无条件链接。
- 需要生成可被其他语言加载的共享库时用 `cc_plugin`，它会把依赖链接进去；`cc_library` 生成的动态库只适合本地运行测试。

## 常用命令

```sh
blade build //storage/...                 # 构建目录及子目录下的所有目标
blade build :segment                      # 当前目录的单个目标
blade build -p debug //storage/segment:segment_tool
blade test //storage/...                  # 构建并运行测试
blade test //storage/segment:segment_test
blade dump --compdb --to-file compile_commands.json   # 供 clangd / clang-tidy 使用
blade dump --config                       # 查看合并后的配置
```

默认 profile 是 `release`。新增源文件或修改依赖后重新生成 `compile_commands.json`。依赖关系可以用 `blade query` 查询，参数以 `blade query --help` 为准。

## 新增代码时的检查

1. 新文件加入正确目标的 `srcs` 或 `hdrs`；公开头文件进 `hdrs`。
2. 新 include 对应的库加入 `deps`；不为了消除报错而把实现库改成 `PUBLIC`。
3. 新目标的 `visibility` 只开放给实际使用方。
4. 运行受影响目录的 `blade build` 与 `blade test`，确认没有新的 missing/unused dependency 诊断。
