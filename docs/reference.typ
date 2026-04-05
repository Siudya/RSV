= RSV Reference

== Class-based modules

- Subclass `RSV::ModuleDef` to define a module.
- Implement module construction in `build(...)` or `initialize(...)`.
- If you override `initialize(...)`, call `super()` before using the DSL.
- Each module object exposes `module_name`. It defaults from the class name (or
  the positional constructor override) and may be reassigned inside `build(...)`
  or `initialize(...)`.
- `Counter.new(...)` at top level returns a module object.
- `Counter.definition(...)` at top level returns a reusable elaborated module
  template handle. If later `definition(...)` calls elaborate to the same
  template, RSV reuses the same handle automatically.
- `Counter.new(...)` inside another module returns a submodule instance handle.
- `RSV::ModuleDef` itself is not instantiated directly.
- When one `ModuleDef` subclass emits multiple distinct SV bodies under the same
  base `module_name`, RSV reuses the first name and appends `_1`, `_2`, ... to
  later variants.

== Declarations

/ `parameter(name, value, type:)`: emits a SystemVerilog parameter declaration.
/ `sv_param(name, default_value)`: class-level macro that declares an SV
  parameter and returns an `SvParamRef` expression node. The ref can be used as
  a width specifier (`uint(WIDTH)`) or in any expression. Enables curried module
  construction: `MyMod.new("name").(WIDTH: 16).(meta: true)`.
  - First `.()` overrides SV parameter defaults.
  - Second `.()` supplies meta parameters passed to `build(**kwargs)`.
/ `bit(init = nil)`: creates an anonymous 1-bit RSV data type.
/ `bits(width = 1, init = nil)`: creates an anonymous unsigned data type. Same as
  `uint`.
/ `uint(width = 1, init = nil)`: alias for `bits`. Creates an anonymous unsigned
  data type.
/ `sint(width = 1, init = nil)`: creates an anonymous signed data type. Emits SV
  `logic signed [...]`.
/ `clock(init = nil)`: creates an anonymous 1-bit clock data type. The returned
  handler supports `.neg` to select negedge: `with_clk_and_rst(clk.neg, rst)` →
  `always_ff @(negedge clk ...)`.
/ `reset(init = nil)`: creates an anonymous 1-bit reset data type. The returned
  handler supports `.neg` for active-low resets:
  `with_clk_and_rst(clk, rst.neg)` → `always_ff @(... negedge rst)` and
  `if (!rst)`.
/ `input(name, type, attr:)`: declares an input port and returns a handler.
/ `output(name, type, attr:)`: declares an output port and returns a handler.
/ `inout(name, type, attr:)`: declares an inout port and returns a handler.
/ `wire(name, type, init:, attr:)`: declares a combinational RSV signal and returns a
  handler. It emits as SV `logic`.
/ `reg(name, type, init:, attr:)`: declares a resettable register-like signal. It emits
  `logic` in SystemVerilog and uses `init` for reset injection in
  domain-driven `always_ff`.
/ `const(name, type, attr:)`: declares a constant. The data type must carry an init
  value (e.g. `sint(16, 0x57)`). Emits as SV `localparam`. The returned handler
  can be used in expressions but cannot appear on the left side of an
  assignment.
/ `arr(dims..., type)` / `arr([dims...], type)`: creates an anonymous packed
  array type. Packed dimensions emit before the scalar width as standard SV
  ranges like `[n-1:0]`. Nested calls flatten:
  `arr([i], arr([j], arr([k], t)))` ≡ `arr([i, j, k], t)`.
/ `mem(dims..., type)` / `mem([dims...], type)`: creates an anonymous unpacked
  memory type. Unpacked dimensions emit after the variable name as standard SV
  ranges like `[n-1:0]`. Nested calls flatten:
  `mem([i], mem([j], mem([k], t)))` ≡ `mem([i, j, k], t)`.
- `arr` and `mem` may be interleaved, but two `arr` calls or two `mem` calls
  cannot swap their relative order.
/ `arr.fill(...)` / `mem.fill(...)`: convenience helpers for building shaped
  reset initializers from anonymous data types that already carry scalar init
  values.
/ `expr(name, rhs, width:)`: infers a wire width, declares a named RSV `wire`
  (emitted as SV `logic`), and emits `assign name = rhs;`.

== Expressions and operators

/ `handler.as_sint`: returns an expression that emits `$signed(handler)` in SV.
  Use to cast an unsigned signal to signed for arithmetic.
/ `mux(sel, a, b)`: ternary mux expression. Emits `sel ? a : b` in SV. When
  `sel` is 1, selects `a`; otherwise selects `b`.
/ `mux1h(sel1h, dats, result:)`: one-hot mux. `sel1h` must be a `wire(uint)`,
  `dats` must be an `arr` or `mem` whose highest dimension length matches the
  width of `sel1h`. Emits `unique casez` with the default branch outputting
  zero.
/ `muxp(sel, dats, result:)`: priority mux. Same signature as `mux1h`. Emits
  `priority casez` with the default branch outputting zero.
/ `expr.sv_take(n)`: starts a stream view and keeps the first `n` elements.
/ `expr.sv_select { |elem, i| ... }`: filters a stream view with a Ruby boolean
  predicate. The index `i` is the original element index and is not renumbered
  after filtering.
/ `expr.sv_foreach { |elem, i| ... }`: eagerly expands one block invocation per
  selected element. Stream sources may be `uint`, `arr(...)`, or `mem(...)`, and
  enumeration always follows the outermost remaining collection dimension.
/ `expr.sv_reduce { |a, b| ... }`: left-folds the selected elements and keeps
  the emitted fold order explicit in SV.
/ `expr.sv_map { |elem, i| ... }`: maps selected elements into a packed result.
  The first mapped element becomes the lowest-position element in the packed
  result, so emitted concatenations appear in reverse order.

== Statements and blocks

/ `with_clk_and_rst(clk, rst)`: sets the implicit clock/reset domain for
  following `always_ff` blocks. Supports `clk.neg` and `rst.neg` for negedge.
/ `definition(source, ...)`: returns a reusable module-definition handle. Accepts
  an RSV module class, an imported module object, or an already-built module /
  definition handle. Identical elaborated templates reuse one cached handle.
/ `instance(def_handle, inst_name:)`: instantiates a reusable definition handle
  and returns the usual mirror-style port handle for later connections.
/ `always_ff { ... }`: emits a domain-driven `always_ff` using the current
  clock/reset.
/ `always_ff(clk, rst) { ... }`: emits an `always_ff` with an explicit domain.
/ `always_latch { ... }`: emits `always_latch begin ... end`.
/ `always_comb { ... }`: emits `always_comb begin ... end`.
/ `svif(cond) { ... }`: convenience wrapper for `if_stmt`.
/ `svelif(cond) { ... }`: convenience wrapper for `elsif_stmt`.
/ `svelse { ... }`: convenience wrapper for `else_stmt`.
/ `lhs <= rhs`: left assignment.
/ `rhs >= lhs`: right assignment.
/ `if_stmt / elsif_stmt / else_stmt`: lower-level procedural control helpers.
/ `to_sv(path = nil)`: returns the generated SV text. Use `to_sv("-")` to write
  to stdout, or `to_sv("build/rtl/foo.sv")` to write to a file.

== Preprocessor macros

/ `sv_def(name, value = nil)`: emits `` `define NAME VALUE ``. Omitting `value`
  emits a bare `` `define NAME ``.
/ `sv_undef(name)`: emits `` `undef NAME ``.
/ `sv_ifdef(name) { ... }`: opens an `` `ifdef NAME `` conditional block.
  Returns a builder that supports `.sv_elif_def(name) { ... }` and
  `.sv_else_def { ... }` chaining.
/ `sv_ifndef(name) { ... }`: same as `sv_ifdef` but emits `` `ifndef ``.
/ `sv_dref(name)`: returns an expression referencing `` `NAME ``. Usable
  wherever a normal RSV expression is expected. Available in both module-level
  and procedural contexts.

== Generate blocks

/ `generate_for(genvar_name, start, end, label: nil) { |i| ... }`:
  emits a `for (genvar ...)` loop. The block receives a genvar reference usable
  as an array index. Local `wire`/`reg`/`const` declarations inside the block
  become block-scoped. `always_ff`, `always_comb`, and `always_latch` may be
  used inside the block.
/ `generate_if(cond, label: nil) { ... }`:
  emits a generate-level `if` block. The condition must be a constant expression
  (e.g., `localparam` or `const` comparison). Returns a builder that supports
  `.generate_elif(cond, label:) { ... }` and `.generate_else(label:) { ... }`
  chaining.

- Both assignment forms emit continuous `assign` outside procedural blocks and
  emit `<=` inside `always_ff`.
- Inside `always_comb` and `always_latch`, assignments emit blocking `=`.
- Comparisons use `eq`, `ne`, `lt`, `le`, `gt`, and `ge`.
- Logical operators use `.and(...)`, `.or(...)`, `!`, `~`, `.or_r`, and `.and_r`.
- Shift operators use `<<` and `>>`.
- Bit and part selects use `sig[i]`, `sig[msb, lsb]` or `sig[msb..lsb]`,
  `sig[base, :+, width]`, and `sig[base, :-, width]`.
- While packed or unpacked `arr(...)` / `mem(...)` dimensions remain on a
  signal, `sig[...]` only accepts a single index. The index must be a hardware
  `uint` or an integer literal. Vector slicing resumes after those dimensions
  are consumed.

== Runtime arithmetic

Non-hardware `uint` and `sint` data types that carry init values can perform
Ruby-time arithmetic. Operations produce a new `DataType` with automatically
inferred width and computed init value:

- Addition and subtraction extend width by 1 bit.
- Multiplication extends width to the sum of operand widths.
- Division preserves LHS width; modulo preserves RHS width.
- Reduction (`or_r`, `and_r`) and comparisons (`eq`, `ne`) produce 1-bit results.

== Submodule connections

- Instantiate submodules by constructing the module class inside another module.
- For repeated variants, prefer `Counter.definition(...)` + `instance(...)` so
  elaboration happens once and the same template is reused.
- Use `inst_name:` to set a deterministic instance name.
- Connect input-like ports with `instance.port <= signal`.
- Connect input-like ports with `signal >= instance.port` if you prefer
  right-assignment form.
- Connect output-like ports with `signal <= instance.port` or
  `instance.port >= signal`.
- Connecting an output instance port directly to an input instance port inserts
  a parent-local `wire` automatically. The wire name is derived from the driving
  instance and port, e.g. `u_tx_dout` or `u_tx_mem_0_1` for indexed /
  multidimensional selections.

== Expression behavior

- Plain Ruby temporaries remain anonymous RSV expressions until they are
  materialized with `expr(...)`.
- For example, `tmp = a + b; out = expr("out", tmp + a)` only emits `out`, and
  the generated assignment keeps the nested expression shape:
  `assign out = a + b + a;`.

== Assignment rules

- `reg(...)` targets may only be assigned inside `always_ff` or `always_latch`.
- `wire(...)` targets may only be assigned by continuous `assign` or inside
  `always_comb`.
- A variable may only be driven from one `assign` or one `always` block.
- Violating these rules raises an argument error before SV emission.

== Naming and style

- Public DSL entry points use snake_case.
- Local RSV `wire`/`reg` declarations are emitted as aligned SV `logic`
  declarations.
- Consecutive continuous `assign` statements align at the `=` column.

== Attributes

- Ports and local declarations accept an optional `attr:` hash.
- Each key is the attribute name; its value is either a string expression or
  `nil` (for standalone attributes).
- Example: `wire("sig", uint(8), attr: { "mark_debug" => "\"true\"" })`
  emits:
  ```systemverilog
  (* mark_debug = "true" *)
  logic [7:0] sig;
  ```
- Example: `output("dout", uint(8), attr: { "keep" => nil })`
  emits:
  ```systemverilog
  (* keep *)
  output logic [7:0] dout
  ```
- Multiple attributes may be combined: `attr: { "a" => nil, "b" => "1" }`
  emits `(* a, b = 1 *)`.

== Verilog compatibility wrapper

- Call `mod.v_wrapper` on a built module to generate a Verilog-compatible
  wrapper with flat ports.
- Packed array ports (e.g. `arr(4, uint(8))`) are flattened to a single
  `[31:0]` bit vector and connected directly.
- Unpacked array ports (e.g. `mem(3, uint(16))`) are expanded to individual
  scalar ports (`port_0`, `port_1`, ...) and reassembled via SV array wires.
- Interface ports are expanded: each interface field becomes a flat Verilog port
  (`port_field`). The wrapper internally instantiates the SV interface and wires
  flat ports to interface fields, respecting modport direction (mst/slv).
- Bundle (struct) ports are expanded: each struct field becomes a flat port
  (`port_field`). Nested bundles are recursively flattened.
- `mem(N, BundleType)` ports expand both the unpacked dimension and the struct
  fields: `port_0_field`, `port_1_field`, etc.
- Interface fields that are bundle-typed are recursively flattened:
  `port_payload_r`, `port_payload_g`, etc.
- A custom wrapper name can be specified: `v_wrapper(wrapper_name: "my_top")`.
- The wrapper output can be written to file: `v_wrapper("path/to/file.sv")`.
- All port widths must be integer constants (not `SvParamRef`) for flattening.
- Example: see `examples/verilog_wrapper.rb`.

== Inline SystemVerilog (sv\_plugin)

- `sv_plugin(code)` embeds raw SystemVerilog code at the current position.
- Usable at module level (emits alongside `assign`, `always`, etc.) and
  inside procedural blocks (`always_ff`, `always_comb`, `always_latch`).
- Multi-line strings (heredocs) are supported; each line is indented to
  match the surrounding context.
- Typical uses: assertions, `$display` debug statements, `function`/`task`
  definitions, vendor-specific pragmas, or any SV construct not yet
  supported by the RSV DSL.
- Example: `sv_plugin '$display("val=%h", sig);'`
- Example: see `examples/sv_plugin_demo.rb`.

== Bundle (Struct)

- Subclass `RSV::BundleDef` to define a packed struct.
- Implement field declarations in `build(...)`.
- `field(name, type)`: declares a struct member. The type can be any RSV data
  type (`bit`, `uint`, `sint`, another bundle, `arr(...)`, `mem(...)`).
  Returns a field handle for use in the Ruby scope. The Ruby variable name
  may differ from the SV field name for encryption-friendly naming.
- `MyBundle.new` returns a `DataType` usable with `input`, `output`, `wire`,
  `reg`, `arr`, `mem`, etc.
- Bundle types emit as `typedef struct packed { ... }` before the module body,
  guarded by ifndef to allow safe multi-file compilation.
- Nested bundles are supported: `field "inner", OtherBundle.new`.
- Parameterized bundles support `sv_param` at class level. Curried call:
  `MyBundle.new.(W: 16)`. Different parameter values produce different
  type names via automatic dedup.
- Partial reset: `reg("r", bundle_t, init: { "field" => 0 })` only generates
  reset assignments for the listed fields in `always_ff`.
- Full reset: provide all field names in the init hash.
- Field access: `handler.field_name` returns a `FieldAccessExpr` usable on
  both sides of assignments. E.g., `r.valid <= 1`, `o <= r.data`.
- Array indexing preserves bundle type: `fifo[0].data` works on
  `mem(N, bundle_t)`.
- Example: see `examples/bundle_and_interface.rb` file.

== Interface

- Subclass `RSV::InterfaceDef` to define a SystemVerilog interface.
- `output(name, type)`: declares an output signal (from the master's
  perspective). Returns a field handle.
- `input(name, type)`: declares an input signal (from the master's
  perspective). Returns a field handle.
- Modports `mst` and `slv` are auto-generated: `mst` keeps declared
  directions, `slv` reverses them.
- Struct (bundle) fields are supported: `output "payload", MyBundle.new`.
- Interface types emit as `interface ... endinterface` with the struct typedefs
  included and both modports auto-synthesized.
- Parameterized interfaces: meta parameters in `build(addr_w: 32, data_w: 32)`.
  `sv_param` at class level also supported.
- `intf_def.to_sv(path)`: emits the interface SV text.
- Module IO integration: `intf(name, IntfClass.new)` declares a master modport
  port; `intf(name, IntfClass.new.slv)` declares a slave modport port.
  Emits `IntfName.mst port_name` or `IntfName.slv port_name`.
- The returned handler supports field access: `bus.data`, `bus.ready`.
- Whole-interface interconnect: `mst <= slv` or `slv >= mst` expands to
  per-field `assign` statements with correct direction based on modport.
  Both sides must have opposite modports (one mst, one slv).
- Individual field assignment: `bus.data <= signal` or `signal <= bus.data`.
- Example: see `examples/bundle_and_interface.rb` file.
