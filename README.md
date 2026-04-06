# RSV — Ruby SystemVerilog Generator

RSV is a lightweight Ruby DSL for generating readable SystemVerilog with a
class-based module API.

RSV covers class-based module construction, anonymous `bit` / `uint` / `sint`
/ `mem` types, procedural blocks, generate blocks, macro helpers,
`BundleDef` (bundle type, flattened to individual signals),
imported black-box modules, Verilog wrapper emission, inline
SystemVerilog escape hatches, automatic module deduplication, and a CLI
entry point (`RSV::App`) for one-command SV export.

## Environment

- Ruby >= 2.7
- xmake
- Typst (optional, for `xmake doc`)
- pyslang

## Installation

```sh
sudo apt install ruby # Ubuntu
pip install pyslang
git clone https://github.com/Siudya/RSV.git
cd RSV
```

## Quick start

```sh
xmake rtl -l              # list examples
xmake rtl -f ctr          # run counter example → build/rtl/
xmake rtl -f syn          # run syntax showcase
xmake doc                 # build PDF documentation
ruby examples/counter.rb -o build/rtl   # direct Ruby invocation
```

For VS Code, use `Ruby LSP` for syntax highlighting, completion, hover, and
go-to-definition, then add `RuboCop` for diagnostics and formatting support.
Keep these gems in Bundler so the editor and the project resolve the same Ruby
environment:

```sh
sudo gem install bundler ruby-lsp
bundle config set --local path vendor/bundle
bundle install
```

Recommended VS Code setting:

```json
{
  "[ruby]": {
    "editor.defaultFormatter": "Shopify.ruby-lsp",
    "editor.formatOnSave": true
  }
}
```

`xmake rtl -l` lists all built-in examples, their 3-4 character aliases, and a
short feature summary. `xmake rtl -f <name-or-alias>` runs a built-in example
from `examples/` and emits RTL into `build/rtl/`.

To run a script from another directory, use:

```sh
xmake rtl -f custom_demo -d path/to/scripts
```

To build the Typst documentation:

```sh
xmake doc
```

This generates `build/rsv_doc.pdf`.

## SystemVerilog feature support

| Area | Support |
| --- | --- |
| Module structure | ports, locals, continuous `assign`, readable alignment |
| Procedural RTL | `always_ff`, `always_comb`, `always_latch`, reset injection, chained `svif`/`svelif`/`svelse` |
| Case statements | `svcase`, `svcasez`, `svcasex` with `unique`/`priority` qualifiers and `?` wildcards |
| Data shapes | unpacked `mem`, indexing and slices |
| Expressions | arithmetic, compare, logical, reduction, shifts, `mux`, `cat`, `fill`, `$signed` |
| Utilities | `log2ceil`, `pop_count`, `mux1h`, `muxp` |
| Elaboration-time features | `generate_for`, `generate_if`, `definition` / `instance`, `meta_param` |
| Bundle types | `BundleDef` (flattened to individual signals at declaration time) |
| SV integration | macro directives, imported SV module signatures, inline `sv_plugin`, Verilog wrapper |
| Examples | `xmake rtl -l` lists runnable examples with aliases and feature summaries |
| CLI entry point | `RSV::App.main(top)` with `-o DIR` for file export, custom options via block form |
| Auto deduplication | Global `ElaborationRegistry` deduplicates module templates; `RSV.export_all(dir)` |

Imported SystemVerilog modules are supported as black-box signatures. RSV reads
their module name, parameters, and ports, then lets you instantiate them from
Ruby DSL code. The imported body is not translated into RSV.

## Project structure

```text
RSV/
├── lib/        # RSV DSL, elaboration, validation, and emission
├── examples/   # Runnable Ruby examples
├── docs/       # Detailed Typst documentation
├── scripts/    # xmake task definitions
├── build/      # Generated PDFs and RTL
└── test/       # Minitest regression tests (按功能分类)
    ├── type_system_test.rb       # 类型系统
    ├── declaration_test.rb       # 声明与对齐
    ├── operator_test.rb          # 运算符与切片
    ├── control_flow_test.rb      # 控制流 (svcase/svif)
    ├── sequential_test.rb        # 时序逻辑 (always_ff/comb/latch)
    ├── expression_test.rb        # 复合表达式 (mux/cat/as_type)
    ├── array_memory_test.rb      # 数组与存储器
    ├── bundle_test.rb            # Bundle 类型
    ├── stream_test.rb            # 流式 API
    ├── module_structure_test.rb  # 模块结构与去重
    ├── macro_generate_test.rb    # 宏与 generate
    ├── integration_test.rb       # 集成 (plugin/wrapper/import)
    ├── examples_suite_test.rb    # 全示例集成验证
    ├── xmake_doc_test.rb         # 文档构建测试
    └── xmake_rtl_test.rb         # RTL 构建测试
```

## Documentation

- [Documentation overview](docs/index.typ)
- [Guide](docs/guide.typ)
- [Reference](docs/reference.typ)
- [Examples and feature coverage](docs/examples.typ)

## Reference links

- [xmake documentation](https://xmake.io)
- [Typst documentation](https://typst.app/docs)
- [Apache 2.0 license](LICENSE)
