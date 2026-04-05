= RSV Guide

This guide covers the normal RSV workflow: define a module class, declare
signals, build expressions, describe procedural behavior, and emit
SystemVerilog.

== Workflow

+ Define a Ruby class that inherits from `RSV::ModuleDef`.
+ Implement hardware construction in `build(...)` or `initialize(...)`.
+ If you override `initialize(...)`, call `super()` before using the DSL.
+ Declare parameters with `parameter(...)` and anonymous RSV data types with
  `bit(...)`, `uint(...)`, `arr(...)`, and `mem(...)`.
+ Create named ports and locals with `input("name", type)`,
  `output("name", type)`, `wire("name", type)`, and `reg("name", type)`.
+ Use `arr.fill(...)` and `mem.fill(...)` to build shaped reset initializers.
+ Materialize named intermediate wires with `expr(...)`.
+ Describe sequential or combinational behavior with `always_ff`,
  `always_latch`, and `always_comb`.
+ Use left assignment `<=` or right assignment `>=` in user code.
+ Write comparisons with `eq/ne/lt/le/gt/ge`, logical ops with `.and(...)`
  and `.or(...)`, and reductions with `.or_r` / `.and_r`.
+ Use `sig[i]`, `sig[msb, lsb]` or `sig[msb..lsb]`, and `sig[base, :+, w]` /
  `sig[base, :-, w]` for bit-select and slicing.
+ While `arr(...)` / `mem(...)` dimensions remain, `sig[...]` only accepts a
  single index.
+ Emit the final module with `to_sv`, `to_sv("-")`, or `to_sv(path)`.

== Two-pass elaboration

RSV first builds an AST from the Ruby DSL. A second elaboration pass then:

- infers expression widths,
- lowers top-level `<=` / `>=` into continuous `assign`,
- lowers procedural assignment into `<=` inside `always_ff` and `=` elsewhere,
- lowers `expr(...)` into a named RSV `wire` that emits as SV `logic` plus an
  `assign`,
- injects reset branches for `reg(..., init: ...)` inside domain-driven
  `always_ff` blocks,
- validates assignment contexts and single-driver rules before the final SV
  text is emitted.

== Worked example

```ruby
require "rsv"

class Counter < RSV::ModuleDef
  def build(width: 8)
    parameter "WIDTH", width

    clk = input("clk", bit)
    rst = input("rst", bit)
    en = input("en", bit)
    count = output("count", uint("WIDTH"))

    countR = reg("count_r", uint("WIDTH"), init: "'0")
    countNext = expr("count_next", countR + 1)

    countR >= count

    with_clk_and_rst(clk, rst)
    always_ff do
      svif(en) do
        countR <= countNext
      end
    end
  end
end

counter = Counter.new(width: 8)
counter.to_sv("-")
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
  logic [WIDTH-1:0] count_next;

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

== Submodule instantiation

When `Counter.new(...)` is called at top level, it creates a module object. When
it is called inside another module, it creates a submodule instance handle.
Ports are connected later with `<=` or `>=`.

```ruby
class Top < RSV::ModuleDef
  def build
    clk = input("clk", bit)
    rst = input("rst", bit)
    count = output("count", uint(8))

    counter = Counter.new(inst_name: "u_counter", width: 8)
    counter.clk <= clk
    rst >= counter.rst
    counter.count >= count
  end
end
```

== Packed arrays and unpacked memories

Use `arr(...)` to add packed dimensions before the scalar bit width and `mem(...)`
to add unpacked dimensions after the variable name. They build anonymous data
types, so you pass the resulting type to `wire(...)`, `reg(...)`, or a port
declaration. For multiple dimensions, use either `arr([i, j, k], uint(8))` /
`mem([i, j, k], uint(8))` or the variadic forms `arr(i, j, k, uint(8))` /
`mem(i, j, k, uint(8))`.

```ruby
packed = reg("cnt_arr_0", arr([i, j, k], uint(8)))
memory = reg("cnt_mem_0", mem([i, j, k], uint(8)))
mixed = reg("cnt_dat", mem([a, b, c], arr([d, e, f], uint(8))))
filled = reg("cnt_init", mem(16, uint(16)), init: mem.fill(16, uint(16, 0x75)))
```

```systemverilog
logic [i-1:0][j-1:0][k-1:0][7:0] cnt_arr_0;
logic [7:0]                      cnt_mem_0[i-1:0][j-1:0][k-1:0];
logic [d-1:0][e-1:0][f-1:0][7:0] cnt_dat[a-1:0][b-1:0][c-1:0];
logic [15:0]                     cnt_init[15:0];
```

As long as a shaped signal still has `arr(...)` / `mem(...)` dimensions left,
`[]` means index selection only. After those dimensions are consumed, plain
vector indexing and slicing behave the same as before.

== Stream views

Packed scalar `uint(...)` values and packed `arr(...)` values can be treated as
enumerable views with `sv_take`, `sv_select`, `sv_foreach`, `sv_reduce`, and
`sv_map`.

```ruby
always_comb do
  parity <= mask.sv_take(4).sv_reduce { |a, b| a ^ b }
  result <= mask
    .sv_take(8)
    .sv_select { |_, i| i.even? }
    .sv_map { |v, _i| v }
end
```

This emits a left-associated reduction and a packed concatenation whose first
selected element lands in the lowest-position slot of the result:

```systemverilog
always_comb begin
  parity = ((mask[0] ^ mask[1]) ^ mask[2]) ^ mask[3];
  result = {mask[6], mask[4], mask[2], mask[0]};
end
```

== Example scripts

- `examples/counter.rb` generates `build/rtl/counter.sv`.
- `examples/top.rb` instantiates two counters and generates `build/rtl/top.sv`.
- `xmake rtl -f counter` runs `examples/counter.rb`.
- `xmake rtl -f name -d dir` runs `dir/name.rb`, with `dir` defaulting to
  `examples`.
