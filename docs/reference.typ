= RSV Reference

== Declarations

/ `parameter(name, value, type:)`: emits a SystemVerilog parameter declaration.
/ `uint(name, width, init:)`: creates a typed signal specification for
  declarations.
/ `input(signal-spec)`: declares an input port and returns a handler.
/ `output(signal-spec)`: declares an output port and returns a handler.
/ `inout(signal-spec)`: declares an inout port and returns a handler.
/ `wire(signal-spec)`: declares a local wire and returns a handler.
/ `logic(signal-spec)`: declares a local logic signal and returns a handler.
/ `reg(signal-spec)`: declares a resettable register-like signal. It emits
  `logic` in SystemVerilog and uses `init` for reset injection in
  domain-driven `always_ff`.
/ `expr(name, rhs, width:)`: infers a wire width, declares a named wire, and
  emits `assign name = rhs;`.

== Statements and blocks

/ `assign_stmt(lhs, rhs)`: emits a continuous `assign`.
/ `with_clk_and_rst(clk, rst)`: sets the implicit clock/reset domain for
  following `always_ff` blocks.
/ `always_ff { ... }`: emits a domain-driven `always_ff` using the current
  clock/reset.
/ `always_ff(clk, rst) { ... }`: emits an `always_ff` with an explicit domain.
/ `always_ff("posedge clk or negedge rst_n") { ... }`: explicit sensitivity
  form.
/ `always_latch { ... }`: emits `always_latch begin ... end`.
/ `always_comb { ... }`: emits `always_comb begin ... end`.
/ `when_(cond) { ... }`: convenience wrapper for `if_stmt`.
/ `sig <= expr`: emits a non-blocking procedural assignment.
/ `assign(lhs, rhs)`: emits a blocking procedural assignment inside procedural
  blocks.
/ `if_stmt / elsif_stmt / else_stmt`: lower-level procedural control helpers.
/ `instantiate(mod, inst, params:, connections:)`: emits a module instance.

== Expression behavior

- Plain Ruby temporaries remain anonymous RSV expressions until they are
  materialized with `expr(...)`.
- For example, `tmp = a + b; out = expr("out", tmp + a)` only emits `out`, and
  the generated assignment keeps the nested expression shape:
  `assign out = (a + b) + a;`.

== Assignment rules

- `reg(...)` targets may only be assigned inside `always_ff` or `always_latch`.
- `logic(...)` targets may be driven by continuous `assign` statements and by
  `always_comb`.
- Violating the `reg(...)` rule raises an argument error before SV emission.

== Naming and compatibility

- Snake case is the preferred public style.
- `ModuleDef` uses snake_case public method names only.
