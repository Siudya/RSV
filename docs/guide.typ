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
+ Use class-level `sv_param("NAME", default)` to declare SV parameters and
  enable curried construction: `MyMod.new("name").(WIDTH: 16).(meta: val)`.
+ Create named ports and locals with `input("name", type)`,
  `output("name", type)`, `wire("name", type)`, and `reg("name", type)`.
+ Declare constants with `const("name", type)` where the data type carries an
  init value (emits as SV `localparam`).
+ Use `generate_for` and `generate_if` for elaboration-time code generation
  (genvar loops and conditional blocks with local scopes).
+ Use `arr.fill(...)` and `mem.fill(...)` to build shaped reset initializers.
+ Materialize named intermediate wires with `expr(...)`.
+ Describe sequential or combinational behavior with `always_ff`,
  `always_latch`, and `always_comb`.
+ Use `svif`/`svelif`/`svelse` for procedural if chains (chainable syntax
  supported: `svif(c){}.svelif(c){}.svelse{}`). Add `unique:` or `priority:`
  qualifiers as needed.
+ Use `svcase`/`svcasez`/`svcasex` for case statements with `is()` branches
  and `fallin` default. Pass string patterns like `is("4'b1??0")` for casez
  wildcards.
+ Use `log2ceil(n)` to compute bit widths at Ruby time, and
  `cnt <= pop_count(vec)` inside `always_comb` for population count.
+ Adjust `module_name` inside `build(...)` if one Ruby class needs to emit a
  non-default SV module name.
+ Use `Counter.definition(...)` plus `instance(...)` when one elaborated module
  template will be instantiated repeatedly.
+ Use left assignment `<=` or right assignment `>=` in user code.
+ Write comparisons with `eq/ne/lt/le/gt/ge`, logical ops with `.and(...)`
  and `.or(...)`, and reductions with `.or_r` / `.and_r`.
+ Use `sig[i]`, `sig[msb, lsb]` or `sig[msb..lsb]`, and `sig[base, :+, w]` /
  `sig[base, :-, w]` for bit-select and slicing.
+ While `arr(...)` / `mem(...)` dimensions remain, `sig[...]` only accepts a
  single index.
+ Emit the final module with `to_sv` or `to_sv(path)`.

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
counter.to_sv("build/rtl/counter.sv")
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
  assign count      = count_r;

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
Ports are connected later with `<=` or `>=`. For repeated variants, you can
also elaborate once with `Counter.definition(...)` and instantiate that handle
manually. If multiple `definition(...)` calls elaborate to the same SV template,
RSV reuses one cached handle.

When one child module output is connected directly to another child module input,
RSV inserts the parent-local interconnect `wire` automatically. The generated
wire name follows the driving instance and port path, so indexed multidimensional
connections such as `u_src.tx_mem[0][1] <= u_dst.rx_mem[1][2]` produce names
like `u_src_tx_mem_0_1`.

Each module object also carries `module_name`, which defaults from the Ruby
class name unless you override it. If repeated instantiations of one
`ModuleDef` subclass produce different SV bodies while keeping the same base
name, RSV preserves the first name and suffixes later variants with `_1`,
`_2`, and so on so their instantiations stay collision-free.

```ruby
class Top < RSV::ModuleDef
  def build(counter_def:)
    clk = input("clk", bit)
    rst = input("rst", bit)
    count = output("count", uint(8))

    counter = instance(counter_def, inst_name: "u_counter")
    counter.clk <= clk
    rst >= counter.rst
    counter.count >= count
  end
end

counter_def = Counter.definition(width: 8)
top = Top.new(counter_def: counter_def)
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

`uint(...)`, `arr(...)`, and `mem(...)` values can be treated as enumerable
views with `sv_take`, `sv_select`, `sv_foreach`, `sv_reduce`, and `sv_map`.
Enumeration always follows the outermost remaining collection dimension, so
mixed and multi-dimensional shapes can be traversed step by step.

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

Use xmake as the user-facing entry point for bundled examples:

```bash
xmake rtl -l
xmake rtl -f ctr
xmake rtl -f syn
```

- `xmake rtl -l` prints all built-in example names, their 3-4 character aliases,
  and a one-line feature summary.
- `xmake rtl -f <name-or-alias>` runs an example from `examples/`.
- `xmake rtl -f name -d dir` runs `dir/name.rb` for custom scripts outside the
  built-in example catalog.
- See `examples.typ` for the full example catalog and feature coverage matrix.

== Import existing SystemVerilog modules

`RSV.import_sv` imports an external SystemVerilog module as a black-box
signature provider. The imported object exposes the module name, parameters,
and ports so it can be instantiated from RSV like an RSV-defined module.

```ruby
ImportedCounter = RSV.import_sv(
  File.join(__dir__, "imported_counter.sv"),
  top: "ImportedCounter",
  incdirs: [__dir__]
)

class ImportDemo < RSV::ModuleDef
  def build
    clk = input("clk", bit)
    dout = output("dout", uint(12))

    counter = ImportedCounter.new(inst_name: "u_imported_counter", WIDTH: 12)
    counter.clk <= clk
    dout <= counter.dout
  end
end
```

This flow relies on `python3` + `pyslang` and currently imports module
signatures only; it does not translate the imported module body into RSV.

== Bundle (struct) usage

Subclass `RSV::BundleDef` and use `field` inside `build` to declare members.
The class produces a `DataType` usable with all RSV declarations.

```ruby
class Pixel < RSV::BundleDef
  def build
    r = field("r", uint(8))
    g = field("g", uint(8))
    b = field("b", uint(8))
  end
end

class PixProc < RSV::ModuleDef
  def build
    clk = input("clk", clock); rst = input("rst", reset)
    px = reg("px", Pixel.new, init: { "r" => 0, "g" => 0, "b" => 0 })
    with_clk_and_rst(clk, rst)
    always_ff { px.r <= 1 }
  end
end
```

Bundles support:
- Nested bundles: `field "inner", OtherBundle.new`
- `arr`/`mem`: `mem(4, Pixel.new)` → `pixel_t fifo[3:0]`
- `sv_param`: `W = sv_param "W", 8` with curried `Pixel.new.(W: 16)`
- Partial reset: only listed fields get reset in `always_ff`
- Field access: `handler.field_name` for reads and writes
- Field handles: `r = field("r", type)` — Ruby name may differ from SV name

== Interface usage

Subclass `RSV::InterfaceDef` and declare signals with `input` and `output`
(from the master's perspective). Modports `mst` and `slv` are auto-generated.
Use `intf` in a module to connect it, and `.slv` to select the slave modport.

```ruby
class MyBus < RSV::InterfaceDef
  def build
    data  = output("data",  uint(32))
    valid = output("valid", bit)
    ready = input("ready",  bit)
  end
end

class Slave < RSV::ModuleDef
  def build
    bus = intf("bus", MyBus.new.slv)
    o = output("dout", uint(32))
    o <= bus.data
  end
end
```

Interfaces support:
- Struct fields: `output "payload", Pixel.new`
- Auto modports: `mst` (as-declared) and `slv` (reversed)
- Module integration: `intf("name", IntfClass.new.slv)`
- Whole-interface interconnect: `mst <= slv` or `slv >= mst` expands to
  per-field assign statements
- Individual field assignment: `bus.data <= signal`
- Meta parameters in `build(addr_w:, data_w:)`
