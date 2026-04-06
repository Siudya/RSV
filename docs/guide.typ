= RSV Guide

This guide covers the normal RSV workflow: define a module class, declare
signals, build expressions, describe procedural behavior, and emit
SystemVerilog.

== Workflow

+ Define a Ruby class that inherits from `RSV::ModuleDef`.
+ Implement hardware construction in `build(...)` or `initialize(...)`.
+ If you override `initialize(...)`, call `super()` before using the DSL.
+ Declare anonymous RSV data types with
  `bit(...)`, `uint(...)`, and `mem(...)`.
+ Use `build(**kwargs)` keyword arguments as meta parameters to control
  module elaboration: `MyMod.new("name", width: 16, meta: val)`.
+ Create named ports and locals with `input("name", type)`,
  `output("name", type)`, `wire("name", type)`, and `reg("name", type)`.
+ Declare constants with `const("name", type)` where the data type carries an
  init value (emits as SV `localparam`).
+ Use `generate_for` and `generate_if` for elaboration-time code generation
  (genvar loops and conditional blocks with local scopes).
+ Use `mem.fill(...)` to build shaped reset initializers.
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
  `cnt <= pop_count(vec)` for population count. `mux1h`, `muxp`, and
  `pop_count` eagerly create temp wires and return wire handlers that can be
  reused across multiple assignments. Work at module level, inside
  `always_comb`, `always_ff`, or `always_latch`.
+ Adjust `module_name` inside `build(...)` if one Ruby class needs to emit a
  non-default SV module name.
+ Use `Counter.definition(...)` plus `instance(...)` when one elaborated module
  template will be instantiated repeatedly.
+ Use left assignment `<=` or right assignment `>=` in user code.
+ Write comparisons with `eq/ne/lt/le/gt/ge`, logical ops with `.and(...)`
  and `.or(...)`, and reductions with `.or_r` / `.and_r`.
+ Use `sig[i]`, `sig[msb, lsb]` or `sig[msb..lsb]`, and `sig[base, :+, w]` /
  `sig[base, :-, w]` for bit-select and slicing.
+ While `mem(...)` dimensions remain, `sig[...]` only accepts a
  single index.
+ Emit the final module with `to_sv` or `to_sv(path)`.
+ Use `RSV::App.main(top)` as a one-liner CLI entry point, or
  use the block form `RSV::App.main { |app| ... }` for custom options.
+ Run `ruby script.rb -o build/rtl` to export all deduplicated modules
  to a directory, or omit `-o` to print the top module SV to stdout.

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
    clk = input("clk", bit)
    rst = input("rst", bit)
    en = input("en", bit)
    count = output("count", uint(width))

    count_r = reg("count_r", uint(width), init: 0)
    count_next = expr("count_next", count_r + 1)

    count_r >= count

    with_clk_and_rst(clk, rst)
    always_ff do
      svif(en) do
        count_r <= count_next
      end
    end
  end
end

counter = Counter.new(width: 8)
RSV::App.main(counter)
```

== Generated SystemVerilog

```systemverilog
module Counter (
  input  logic       clk,
  input  logic       rst,
  input  logic       en,
  output logic [7:0] count
);

  logic [7:0] count_r;
  logic [7:0] count_next;

  assign count_next = count_r + 8'd1;
  assign count      = count_r;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      count_r <= 8'h0;
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

== Unpacked memories

Use `mem(...)` to add unpacked dimensions after the variable name. This builds
anonymous data types, so you pass the resulting type to `wire(...)`, `reg(...)`,
or a port declaration. For multiple dimensions, use either
`mem([i, j, k], uint(8))` or the variadic form `mem(i, j, k, uint(8))`.

```ruby
memory = reg("cnt_mem_0", mem([i, j, k], uint(8)))
filled = reg("cnt_init", mem(16, uint(16)), init: mem.fill(16, uint(16, 0x75)))
```

```systemverilog
logic [7:0]  cnt_mem_0[i-1:0][j-1:0][k-1:0];
logic [15:0] cnt_init[15:0];
```

As long as a shaped signal still has `mem(...)` dimensions left,
`[]` means index selection only. After those dimensions are consumed, plain
vector indexing and slicing behave the same as before.

== Stream views

`uint(...)` and `mem(...)` values can be treated as enumerable
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

== Bundle usage

Subclass `RSV::BundleDef` and use `input`/`output` inside `build` to declare
members with direction annotations. The class produces a `DataType` usable with
all RSV declarations. Bundle fields are flattened to individual signals at
declaration time. Direction is respected only for IO ports (`iodecl`); local
signals (`reg`/`wire`) ignore direction.

```ruby
class Pixel < RSV::BundleDef
  def build
    r = input("r", uint(8))
    g = input("g", uint(8))
    b = input("b", uint(8))
  end
end

class PixProc < RSV::ModuleDef
  def build
    clk = input("clk", clock); rst = input("rst", reset)
    px_in  = iodecl("px_in", Pixel.new)        # fields keep their dirs
    px_out = iodecl("px_out", flip(Pixel.new))  # dirs reversed
    px = reg("px", Pixel.new, init: { "r" => 0, "g" => 0, "b" => 0 })
    with_clk_and_rst(clk, rst)
    px_out <= px
    always_ff { px.r <= px_in.r }
  end
end
```

A `reg("px", Pixel.new)` declaration generates three separate signals:
`px_r`, `px_g`, `px_b`. Field access `px.r` maps directly to `px_r`.

Bundles support:
- Nested bundles: `input "inner", OtherBundle.new` (recursively flattened)
- `mem`: `mem(4, Pixel.new)` → separate signals with unpacked dim
- Meta parameters: `def build(w: 8)` with `Pixel.new(w: 16)`
- Partial reset: only listed fields get reset in `always_ff`
- Field access: `handler.field_name` for reads and writes
- Field handles: `r = input("r", type)` — Ruby name may differ from SV name
- Whole-bundle assignment: `out <= reg` expands to per-field assignments
- IO declarations: `iodecl("name", bundle)` uses field directions;
  `iodecl("name", flip(bundle))` reverses all directions
- Scalar IO: `iodecl("name", output(uint(8)))` or `iodecl("name", input(type))`

== Type Conversion with `as_type`

Any signal can be converted to a different data type using `.as_type(target)`:

```ruby
# Scalar → scalar (truncate / zero-extend)
narrow <= wide.as_type(uint(8))     # keeps LSBs
wide   <= narrow.as_type(uint(32))  # pads MSBs with zeros

# Bundle → uint (flatten)
flat <= pxl.as_type(uint(24))  # same as pxl.as_uint

# uint → bundle (reshape)
pxl = data.as_type(Pixel.new)
out <= pxl.r

# uint → mem (slice into elements)
m = data.as_type(mem(4, uint(8)))
out <= m[2]

# uint → mem(bundle)
mb = data.as_type(mem(2, Pixel.new))
out <= mb[1].g
```

Width mismatch is handled automatically:
- Source wider than target → truncate (keep LSBs)
- Source narrower than target → zero-extend (pad MSBs)

== CLI entry point: `RSV::App`

`RSV::App` provides a unified command-line interface for RSV scripts. It
supports a built-in `-o/--out-dir DIR` option for exporting deduplicated SV
files to a directory, and allows user-defined options via `app.option(...)`.

=== Simplest form

```ruby
counter = Counter.new(width: 8)
RSV::App.main(counter)
```

Run with:

```bash
ruby counter.rb -o build/rtl      # → writes build/rtl/counter.sv
ruby counter.rb                   # → prints SV to stdout
```

=== Custom options and build logic

```ruby
RSV::App.main do |app|
  app.option(:width, "-w", "--width WIDTH", Integer, "Data width", default: 8)
  app.build { |opts| Counter.new(width: opts[:width]) }
end
```

=== Post-export callback

```ruby
RSV::App.main do |app|
  app.build { |opts| [ModA.new, ModB.new] }
  app.after_export do |opts, tops|
    tops.each { |t| t.v_wrapper(File.join(opts[:out_dir], "#{t.module_name}_wrapper.sv")) } if opts[:out_dir]
  end
end
```

=== Multiple top modules

```ruby
RSV::App.main([PixelProcessor.new, PacketRouter.new])
```

== Automatic module deduplication

When a `ModuleDef` subclass is elaborated, its SV body is automatically
registered in a global `ElaborationRegistry`. If the same class is elaborated
with the same parameters (producing identical SV), only one copy is stored.

`RSV.export_all(dir)` writes one `.sv` file per unique module template.
When using `RSV::App.main` with `-o DIR`, this is done automatically.

Modules that have the same base class name but differ in elaborated SV bodies
receive suffixed names (`_1`, `_2`, etc.) to avoid collisions.
