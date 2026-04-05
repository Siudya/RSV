# RSV — Ruby SystemVerilog Generator

RSV is a lightweight Ruby DSL for generating readable SystemVerilog with a
class-based module API.

Current DSL highlights include anonymous `bit` / `uint` / `arr` / `mem` data
types, class-based module construction, and stream-view operations on `uint`
and packed `arr` values (`sv_take`, `sv_select`, `sv_foreach`, `sv_reduce`,
`sv_map`).

## Environment

- Ruby >= 2.7
- xmake
- Typst (optional, for `xmake doc`)
- pyslang

## Installation

```sh
pip install pyslang
git clone https://github.com/Siudya/RSV.git
cd RSV
```

## Quick start

Run the bundled examples:

```sh
ruby examples/counter.rb
ruby examples/top.rb
```

Both examples print generated SystemVerilog with `to_sv("-")` and write the
results to `build/rtl/`.

Use xmake automation:

```sh
xmake rtl -f counter
xmake doc
```

These generate `build/rtl/*.sv` and `build/rsv_doc.pdf`.

## Import existing SystemVerilog modules

`RSV.import_sv` can import an external SystemVerilog module as a black-box
signature provider. The imported object exposes the module name, parameters,
and ports, and can be instantiated inside RSV modules just like an RSV-defined
module.

```ruby
Uart = RSV.import_sv("vendor/uart.sv", top: "Uart", incdirs: ["vendor/include"])

class Top < RSV::ModuleDef
  def build
    clk = input("clk", bit)
    tx = output("tx", bit)

    uart = Uart.new(inst_name: "u_uart", WIDTH: 16)
    uart.clk <= clk
    tx <= uart.tx
  end
end
```

This importer uses `python3` + `pyslang` under the hood and currently imports
module signatures only; it does not translate the imported module body into
RSV.

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

## Reference links

- [xmake documentation](https://xmake.io)
- [Typst documentation](https://typst.app/docs)
- [Apache 2.0 license](LICENSE)
