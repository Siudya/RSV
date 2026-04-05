# RSV — Ruby SystemVerilog Generator

RSV is a lightweight Ruby DSL for generating readable SystemVerilog with a
class-based module API.

RSV covers class-based module construction, anonymous `bit` / `uint` / `sint`
/ `arr` / `mem` types, procedural blocks, generate blocks, macro helpers,
`BundleDef` (struct) and `InterfaceDef` (interface) constructs,
imported black-box modules, Verilog wrapper emission, and inline
SystemVerilog escape hatches.

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
xmake rtl -l
xmake rtl -f ctr
xmake rtl -f syn
xmake doc
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
| Module structure | parameters, ports, locals, continuous `assign`, readable alignment |
| Procedural RTL | `always_ff`, `always_comb`, `always_latch`, reset injection, `if` / `else` |
| Data shapes | packed `arr`, unpacked `mem`, mixed shapes, indexing and slices |
| Expressions | arithmetic, compare, logical, reduction, shifts, `mux`, `cat`, `fill`, `$signed` |
| Elaboration-time features | `generate_for`, `generate_if`, `definition` / `instance`, curried `sv_param` |
| Struct & Interface | `BundleDef` (packed struct typedef), `InterfaceDef` (interface + modport), `interface_port` |
| SV integration | macro directives, imported SV module signatures, inline `sv_plugin`, Verilog wrapper |
| Examples | `xmake rtl -l` lists runnable examples with aliases and feature summaries |

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
└── test/       # Minitest regression tests
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
