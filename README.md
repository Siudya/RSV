# RSV — Ruby SystemVerilog 生成器

RSV 是一个轻量级 Ruby DSL，用来生成可读、语义清晰的 SystemVerilog。它以类式模块 API 为核心，适合在 Ruby 展开期组织硬件结构，再导出为标准 SV 文件。

当前仓库覆盖的能力包括：模块与端口声明、匿名 `bit` / `uint` / `sint` / `vec` 类型、`always_ff` / `always_comb` / `always_latch`、`svif` / `svcase`、`generate` 块、`BundleDef` 扁平展开、导入外部 SystemVerilog 模块签名、`sv_plugin` 内嵌 SV、Verilog 兼容封装层、自动模块去重，以及 `RSV::App` 命令行导出入口。

## 常用声明方式

推荐使用统一的 `let` 形式；需要显式端口名时可用 `iodecl`；内部信号也可以直接使用 `wire` / `reg` / `const` / `expr`。

```ruby
# let 形式（推荐）
let :clk, input(clock)
let :cnt, reg(uint(16), init: 0x15)

# iodecl / 直接声明形式
clk = iodecl("clk", input(clock))
cnt = reg("cnt", uint(16), init: 0x15)
```

## 环境依赖

- Ruby >= 2.7
- xmake
- `python3` + `pyslang`
- Typst（可选，用于 `xmake doc`）
- Verilator（可选，用于 RTL lint）

## 安装

下面是一套最小安装流程；`xmake`、Typst 与 Verilator 请按各自官方文档安装。

```sh
sudo apt install ruby python3-pip
git clone https://github.com/Siudya/RSV.git
cd RSV
pip install pyslang
bundle config set --local path vendor/bundle
bundle install
```

## 快速上手

```sh
xmake rtl -l                    # 列出内置示例、别名与特性摘要
xmake rtl -f ctr                # 运行 counter 示例，输出到 build/rtl/
xmake rtl -f syn                # 运行 syntax_showcase 示例
xmake doc                       # 生成 PDF 文档
ruby examples/counter.rb -o build/rtl   # 直接运行 Ruby 脚本导出 RTL
```

`xmake rtl -l` 会列出 `examples/` 中的全部内置示例、3-4 字符别名和一句话特性摘要。`xmake rtl -f <名称或别名>` 会执行对应脚本，并把生成的 RTL 写入 `build/rtl/`。若要运行自定义目录下的脚本，可使用：

```sh
xmake rtl -f custom_demo -d path/to/scripts
```

Typst 文档可通过下面的命令构建，输出文件为 `build/rsv_doc.pdf`：

```sh
xmake doc
```

## 核心能力

| 领域 | 当前支持 |
| --- | --- |
| 模块结构 | 端口、局部信号、连续 `assign`、对齐后的可读 SV 输出 |
| 过程化 RTL | `always_ff`、`always_comb`、`always_latch`、复位注入、链式 `svif` / `svelif` / `svelse` |
| 分支语句 | `svcase`、`svcasez`、`svcasex`，支持 `unique` / `priority` 与 `?` 通配 |
| 数据形态 | 非打包 `vec`、索引、切片、Bundle 打平 |
| 表达式 | 算术、比较、逻辑、归约、移位、`mux`、`cat`、`fill`、`$signed` |
| 常用工具 | `log2ceil`、`pop_count`、`mux1h`、`muxp` |
| 展开期能力 | `generate_for`、`generate_if`、`definition` / `instance`、meta 参数 |
| Bundle 类型 | `BundleDef` 在声明时展开为独立信号，支持嵌套与 `vec` 组合 |
| SV 集成 | 宏指令、`RSV.import_sv`、内嵌 `sv_plugin`、Verilog 兼容封装层 |
| 命令行与导出 | `xmake rtl`、`xmake doc`、`RSV::App.main(top)`、`RSV.export_all(dir)` |
| 自动去重 | 全局 `ElaborationRegistry` 按展开后的模块模板去重，并为变体自动加后缀 |

通过 `RSV.import_sv` 导入的 SystemVerilog 模块当前只读取模块名、参数和端口签名，用作黑盒例化；导入模块本体不会被翻译成 RSV DSL。

## 仓库结构

```text
RSV/
├── lib/        # RSV DSL、展开、验证、发射器与命令行入口
├── examples/   # 可直接运行的 Ruby 示例
├── docs/       # Typst 文档源文件
├── scripts/    # xmake 任务定义
├── build/      # 文档与 RTL 输出目录
└── test/       # Minitest 回归测试
```

`test/` 目录按能力分组，涵盖类型系统、声明与对齐、操作符、控制流、时序逻辑、数组与存储器、Bundle、流式 API、模块结构、宏与 generate、集成、示例构建、文档构建与 xmake 入口。

## 文档入口

- [文档总览](docs/index.typ)
- [使用指南](docs/guide.typ)
- [DSL 参考](docs/reference.typ)
- [示例与特性覆盖](docs/examples.typ)

## 编辑器建议

VS Code 可使用 `Ruby LSP` 提供高亮、补全、悬停与跳转，再配合 `RuboCop` 提供诊断与格式化。建议让编辑器与项目共用同一套 Bundler 环境：

```sh
sudo gem install bundler ruby-lsp
bundle config set --local path vendor/bundle
bundle install
```

推荐设置：

```json
{
  "[ruby]": {
    "editor.defaultFormatter": "Shopify.ruby-lsp",
    "editor.formatOnSave": true
  }
}
```

## 常用验证命令

```sh
for f in test/*_test.rb; do ruby -Ilib "$f"; done
xmake doc
xmake rtl -l
xmake rtl -f counter
verilator --lint-only build/rtl/counter.sv
```

其中 `test/examples_suite_test.rb` 会批量生成全部内置示例，并对对应 SV 结果运行 `verilator --lint-only`。

## 参考链接

- [xmake 文档](https://xmake.io)
- [Typst 文档](https://typst.app/docs)
- [Apache 2.0 许可证](LICENSE)
