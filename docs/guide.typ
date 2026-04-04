= RSV Guide

This guide covers the normal RSV workflow: declare signals, build expressions,
describe procedural behavior, and emit SystemVerilog.

== Workflow

+ Declare parameters and typed signals with `parameter(...)` and `uint(...)`.
+ Create ports and locals with `input(...)`, `output(...)`, `wire(...)`,
  `logic(...)`, and `reg(...)`.
+ Materialize named intermediate wires with `expr(...)`.
+ Describe sequential or combinational behavior with `always_ff`,
  `always_latch`, and `always_comb`.
+ Emit the final module with `to_sv`.

== Two-pass elaboration

RSV first builds an AST from the Ruby DSL. A second elaboration pass then:

- infers expression widths,
- lowers `expr(...)` into `wire` plus `assign`,
- injects reset branches for `reg(..., init: ...)` inside domain-driven
  `always_ff` blocks,
- validates assignment contexts before the final SV text is emitted.

== Worked example

```ruby
require "rsv"

counter = RSV::ModuleDef.new("Counter") do
  parameter "WIDTH", 8

  clk = input(uint("clk"))
  rst = input(uint("rst"))
  en = input(uint("en"))
  count = output(uint("count", width: "WIDTH"))

  countR = reg(uint("count_r", width: "WIDTH", init: "'0"))
  countNext = expr("count_next", countR + 1)

  assign_stmt(count, countR)

  with_clk_and_rst(clk, rst)
  always_ff do
    when_(en) do
      countR <= countNext
    end
  end
end

puts counter.to_sv
```

== Generated SystemVerilog

```systemverilog
module Counter #(
  parameter int WIDTH = 8
) (
  input  logic             clk,
  input  logic             rst,
  input  logic             en,
  output logic [WIDTH-1:0] count
);

  logic [WIDTH-1:0] count_r;
  wire [WIDTH-1:0] count_next;

  assign count_next = count_r + 1;
  assign count = count_r;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      count_r <= '0;
    end else if (en) begin
      count_r <= count_next;
    end
  end

endmodule
```

== Example scripts

- `examples/counter.rb` generates `build/rtl/counter.sv`.
- `examples/top.rb` instantiates two counters and generates `build/rtl/top.sv`.
- `xmake rtl -f counter` runs `examples/counter.rb`.
- `xmake rtl -f name -d dir` runs `dir/name.rb`, with `dir` defaulting to
  `examples`.
