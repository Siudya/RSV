# RSV — Ruby SystemVerilog Generator

RSV is a lightweight Ruby DSL for generating readable SystemVerilog. It keeps
module structure close to native SV while making signal declarations,
expressions, and procedural blocks easier to describe in Ruby.

## Environment

- Ruby >= 2.7
- xmake
- No gem dependencies
- Typst (optional, for compiling the detailed docs in `docs/`)

## Installation

```sh
git clone https://github.com/Siudya/RSV.git
cd RSV
```

## Quick start

Run the bundled examples:

```sh
ruby examples/counter.rb
ruby examples/top.rb
```

Both examples print generated SystemVerilog to stdout and write the results to
`build/rtl/`.

Build the Typst documentation with xmake:

```sh
xmake doc
```

This generates `build/rsv_doc.pdf`.

Run an RTL example or other Ruby generator script with xmake:

```sh
xmake rtl -f counter
```

## Project structure

```text
RSV/
├── lib/        # RSV DSL, elaboration, validation, and emission
├── examples/   # Runnable Ruby examples
├── docs/       # Detailed Typst documentation
├── build/      # Generated automation outputs such as rsv_doc.pdf and RTL
├── test/       # Minitest regression tests
└── out/        # Generated SystemVerilog output
```

## Documentation

- [Documentation overview](docs/index.typ)
- [Guide](docs/guide.typ)
- [Reference](docs/reference.typ)

## Reference links

- [xmake documentation](https://xmake.io)
- [Typst documentation](https://typst.app/docs)
- [Apache 2.0 license](LICENSE)
