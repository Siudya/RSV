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
/ `mux1h(sel1h, dats)`: one-hot mux. Auto-creates a temp wire and `always_comb`
  with `unique casez`. `dats` must be an `arr` or `mem` whose highest dimension
  length matches `sel1h` width. Usage: `out <= mux1h(sel, dats)` — works at
  module level, in `always_comb`, `always_ff`, or `always_latch`.
/ `muxp(sel, dats, lsb_first: true)`: priority mux. Same as `mux1h` but
  emits `priority casez`. The `lsb_first:` option controls priority order.
/ `pop_count(vec)`: population count. Auto-creates a temp wire and `always_comb`
  with a for-loop accumulator. Counts 1-bits in `vec`. Output width is
  `log2ceil(vec.width + 1)`. Usage: `out <= pop_count(vec)` — works at
  module level, in `always_comb`, `always_ff`, or `always_latch`.
/ `log2ceil(n)`: pure Ruby utility. Returns `ceil(log2(n))` — the minimum number
  of bits to address `n` items. Available in module `build` blocks and as `RSV.log2ceil(n)`.
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
/ `svif(cond, unique: false, priority: false) { ... }`: procedural if statement.
  Set `unique: true` or `priority: true` to emit `unique if` or `priority if`.
  Returns a chainable object — use `.svelif(cond) { ... }` and `.svelse { ... }` for
  compact if/elsif/else chains (standalone `svelif`/`svelse` calls also work).
/ `svelif(cond) { ... }`: else-if branch (appends to preceding `svif`).
/ `svelse { ... }`: else branch.
/ `svcase(expr, unique: false, priority: false) { ... }`: procedural case statement.
  Inside the block, use `is(val, ...) { ... }` for branches and `fallin { ... }`
  for the default branch. Multiple values in `is` emit comma-separated match.
/ `svcasez(expr, unique: false, priority: false) { ... }`: casez statement.
  Use string values like `is("4'b1??0")` for `?` wildcard patterns.
/ `svcasex(expr, unique: false, priority: false) { ... }`: casex statement.
/ `lhs <= rhs`: left assignment.
/ `rhs >= lhs`: right assignment.
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
- Bundle ports are already flattened at declaration time: each bundle field
  becomes a separate port (`port_field`). Nested bundles are recursively
  flattened (`port_inner_field`).
- `mem(N, BundleType)` ports: each flattened field carries the unpacked dimension.
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

== Bundle

- Subclass `RSV::BundleDef` to define a bundle type.
- Implement field declarations in `build(...)` using direction annotations.
- `input(name, type)`: declares an input-directed bundle field.
- `output(name, type)`: declares an output-directed bundle field.
  Returns a field handle for use in the Ruby scope. The Ruby variable name
  may differ from the SV field name for encryption-friendly naming.
- `MyBundle.new` returns a `DataType` usable with `iodecl`, `wire`,
  `reg`, `arr`, `mem`, etc.
- Bundle fields are flattened to individual signals at declaration time.
  E.g. `reg("px", Pixel.new)` produces `px_r`, `px_g`, `px_b`.
- Nested bundles are recursively flattened: `outer_inner_field`.
- Parameterized bundles use `build(**kwargs)` meta parameters. Call:
  `MyBundle.new(w: 16)`. Different parameter values produce different
  type names via automatic dedup.
- Partial reset: `reg("r", bundle_t, init: { "field" => 0 })` only generates
  reset assignments for the listed fields in `always_ff`.
- Full reset: provide all field names in the init hash.
- Field access: `handler.field_name` returns the flattened signal handler.
  E.g., `r.valid <= 1`, `o <= r.data`.
- Whole-bundle assignment: `out <= reg` expands to per-field assignments.
- Array indexing preserves bundle grouping: `fifo[0].data` works on
  `mem(N, bundle_t)`.

=== IO Declarations with Bundles

- `iodecl(name, bundle_type)`: declares IO ports using each field's direction.
- `iodecl(name, flip(bundle_type))`: reverses all field directions (input↔output).
- `iodecl(name, output(type))`: declares a scalar output port.
- `iodecl(name, input(type))`: declares a scalar input port.
- `iodecl(name, output(mem(N, type)))`: declares an output port with unpacked dims.
- Local declarations (`reg`, `wire`) ignore field direction — all fields become
  plain `logic`.
- Example: see `examples/bundle_and_interface.rb` file.
