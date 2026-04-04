# RSV — Ruby SystemVerilog Generator

RSV is a lightweight Ruby DSL for generating readable, semantic-preserving
SystemVerilog code.  It acts as syntax sugar over SystemVerilog, letting you
write concise Ruby while retaining SV's native constructs — parameterized
modules, typed logic signals, `always_ff` / `always_comb`, continuous
assignments, and module instantiation.  The output is clean, near-hand-written
SV that any downstream tool (Verilator, Slang, VCS, …) can consume directly.

## Design philosophy

| Principle | What it means in practice |
|---|---|
| **SV-first** | Ruby is a friendlier front-end; every construct maps 1-to-1 to a SV statement |
| **Preserve semantics** | Parameters, widths, and signal names pass through unchanged — no lossy lowering |
| **Human-readable output** | Formatted, column-aligned ports; idiomatic `begin/end` blocks |
| **Zero dependencies** | Uses only the Ruby standard library |

## Requirements

- **Ruby ≥ 2.7** (tested on 3.x)
- No gems required

## Installation

```sh
git clone https://github.com/Siudya/RSV.git
cd RSV
```

That's it — no `bundle install` needed.

## Running the examples

### Counter (parameterized synchronous counter with active-low reset)

```sh
ruby examples/counter.rb
```

Prints the generated SV to stdout **and** writes `out/counter.sv`.

### Top-level instantiation (two Counter instances with different widths)

```sh
ruby examples/top.rb
```

Prints the generated SV to stdout **and** writes `out/top.sv`.

## DSL reference

### Module definition

```ruby
require_relative "lib/rsv"

mod = RSV::ModuleDef.new("MyModule") do
  # parameters
  parameter "WIDTH", 8          # parameter int WIDTH = 8

  # ports
  input  "clk"
  input  "rst_n"
  input  "data_in",  width: "WIDTH"
  output "data_out", width: "WIDTH"
  inout  "bus",      width: 4

  # internal logic
  logic "pipe_r", width: "WIDTH"

  # continuous assignment
  assign_stmt "data_out", "pipe_r"

  # always_ff block
  always_ff "posedge clk or negedge rst_n" do
    if_stmt "!rst_n" do
      nb_assign "pipe_r", "'0"
    end
    elsif_stmt "en" do
      nb_assign "pipe_r", "data_in"
    end
  end

  # always_comb block
  always_comb do
    assign "data_out", "pipe_r ^ 8'hFF"
  end

  # module instantiation
  instantiate "SubModule", "u_sub",
    params:      { "WIDTH" => 8 },
    connections: { "clk" => "clk", "data" => "pipe_r" }
end

puts mod.to_sv
```

### DSL method summary

| Method | SV construct |
|---|---|
| `parameter(name, val, type:)` | `parameter <type> NAME = val` |
| `input(name, width:, signed:)` | `input logic [W-1:0] name` |
| `output(name, width:, signed:)` | `output logic [W-1:0] name` |
| `inout(name, width:)` | `inout logic [W-1:0] name` |
| `logic(name, width:, signed:)` | `logic [W-1:0] name;` |
| `assign_stmt(lhs, rhs)` | `assign lhs = rhs;` |
| `always_ff(sensitivity) { }` | `always_ff @(…) begin … end` |
| `always_comb { }` | `always_comb begin … end` |
| `nb_assign(lhs, rhs)` *(inside always block)* | `lhs <= rhs;` |
| `assign(lhs, rhs)` *(inside always block)* | `lhs = rhs;` |
| `if_stmt(cond) { }` *(inside always block)* | `if (cond) begin … end` |
| `elsif_stmt(cond) { }` *(inside always block)* | `end else if (cond) begin … end` |
| `else_stmt { }` *(inside always block)* | `end else begin … end` |
| `instantiate(mod, inst, params:, connections:)` | `ModName #(…) instName (…);` |

## DSL example and generated output

**Ruby DSL** (`examples/counter.rb`):

```ruby
counter = RSV::ModuleDef.new("Counter") do
  parameter "WIDTH", 8

  input  "clk"
  input  "rst_n"
  input  "en"
  output "count", width: "WIDTH"

  logic "count_r", width: "WIDTH"

  assign_stmt "count", "count_r"

  always_ff "posedge clk or negedge rst_n" do
    if_stmt "!rst_n" do
      nb_assign "count_r", "'0"
    end
    elsif_stmt "en" do
      nb_assign "count_r", "count_r + 1'b1"
    end
  end
end

puts counter.to_sv
```

**Generated SystemVerilog**:

```systemverilog
module Counter #(
  parameter int WIDTH = 8
) (
  input  logic             clk,
  input  logic             rst_n,
  input  logic             en,
  output logic [WIDTH-1:0] count
);

  logic [WIDTH-1:0] count_r;

  assign count = count_r;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      count_r <= '0;
    end else if (en) begin
      count_r <= count_r + 1'b1;
    end
  end

endmodule
```

## Project structure

```
RSV/
├── lib/
│   ├── rsv.rb                      # Main entry point (require this)
│   └── rsv/
│       ├── nodes.rb                # AST node classes
│       ├── procedural_builder.rb   # Builder for always_ff / always_comb blocks
│       ├── module_def.rb           # ModuleDef DSL class
│       └── emitter.rb              # SystemVerilog text emitter
├── examples/
│   ├── counter.rb                  # Parameterized counter demo
│   └── top.rb                      # Top-level instantiation demo
└── out/                            # Generated .sv files (git-ignored)
```

## License

[Apache 2.0](LICENSE)
