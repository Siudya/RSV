# frozen_string_literal: true
# examples/syntax_showcase.rb
#
# A deliberately dense module that demonstrates the "small syntax" of RSV in one
# place: declarations, operators, slices, casts, combinational logic, latches,
# and the domain-sharing `with_clk_and_rst` workflow.
#
# Covered syntax:
# - `bit`, `bits`, `uint`, `sint`, `clock`, `reset`, `inout`
# - `wire`, `reg`, `expr`
# - Ruby-time `DataType` arithmetic for declaration-time constants
# - continuous assignments with both `<=` and `>=`
# - arithmetic / compare / logical / reduction operators
# - part-selects, indexed part-selects, `cat`, `fill`, `mux`
# - `always_comb`, `always_latch`, `with_clk_and_rst`, `always_ff`
# - `svif`, `svelif`, `svelse`
#
# Run:
#   ruby examples/syntax_showcase.rb

$LOAD_PATH.unshift(File.join(__dir__, "..", "lib"))
require "rsv"

class SyntaxShowcase < RSV::ModuleDef
  def build
    clk = input("clk", clock)
    rst_n = input("rst_n", reset)
    gate = input("gate", bit)
    load = input("load", bit)
    sel = input("sel", bit)
    pad = inout("pad", bit)
    a = input("a", uint(8))
    b = input("b", uint(8))
    signed_b = input("signed_b", sint(8))
    bus = input("bus", uint(16))
    nibble = input("nibble", bits(4))

    sum_o = output("sum_o", uint(8))
    right_assign_o = output("right_assign_o", uint(8))
    eq_o = output("eq_o", bit)
    ne_o = output("ne_o", bit)
    lt_o = output("lt_o", bit)
    le_o = output("le_o", bit)
    gt_o = output("gt_o", bit)
    ge_o = output("ge_o", bit)
    logic_and_o = output("logic_and_o", bit)
    logic_or_o = output("logic_or_o", bit)
    red_or_o = output("red_or_o", bit)
    red_and_o = output("red_and_o", bit)
    not_o = output("not_o", bit)
    pad_sample_o = output("pad_sample_o", bit)
    bit_inv_o = output("bit_inv_o", uint(8))
    shl_o = output("shl_o", uint(8))
    shr_o = output("shr_o", uint(8))
    mul_o = output("mul_o", uint(8))
    div_o = output("div_o", uint(8))
    mod_o = output("mod_o", uint(8))
    range_o = output("range_o", uint(4))
    range_alt_o = output("range_alt_o", uint(4))
    indexed_up_o = output("indexed_up_o", uint(4))
    indexed_down_o = output("indexed_down_o", uint(4))
    mux_o = output("mux_o", uint(8))
    comb_o = output("comb_o", uint(8))
    cat_o = output("cat_o", uint(8))
    fill_o = output("fill_o", uint(8))
    signed_sum_o = output("signed_sum_o", sint(8))
    latch_o = output("latch_o", uint(8))
    ff_o = output("ff_o", uint(8))
    neg_ff_o = output("neg_ff_o", uint(8))

    # `DataType` values with init data can be combined at Ruby time. Here the
    # result is used as a declaration-time constant, and the generated SV shows
    # the derived width and init value directly.
    runtime_seed_t = uint(8, 5) + uint(8, 2)
    seed = wire("seed", uint(runtime_seed_t.width), init: runtime_seed_t.init)

    # `expr(...)` materializes an inferred logic signal while keeping the Ruby
    # expression readable at the call site.
    sum_next = expr("sum_next", a + b)
    signed_sum_w = wire("signed_sum_w", sint(8))
    comb_w = wire("comb_w", uint(8))
    latch_q = reg("latch_q", uint(8))
    ff_q = reg("ff_q", uint(8), init: 0)
    neg_ff_q = reg("neg_ff_q", uint(8), init: 0)

    # Continuous assignments cover the basic expression forms.
    sum_next >= sum_o
    a >= right_assign_o
    eq_o <= a.eq(b)
    ne_o <= a.ne(b)
    lt_o <= a.lt(b)
    le_o <= a.le(b)
    gt_o <= a.gt(b)
    ge_o <= a.ge(b)
    logic_and_o <= a.lt(b).and(gate)
    logic_or_o <= a.gt(b).or(sel)
    red_or_o <= nibble.or_r
    red_and_o <= nibble.and_r
    not_o <= !sel
    pad_sample_o <= pad
    bit_inv_o <= ~a
    shl_o <= a << 1
    shr_o <= b >> 1
    mul_o <= a * b
    div_o <= a / 3
    mod_o <= a % 3
    range_o <= bus[15, 12]
    range_alt_o <= bus[15..12]
    indexed_up_o <= bus[4, :+, 4]
    indexed_down_o <= bus[11, :-, 4]
    mux_o <= mux(sel, a, b)
    cat_o <= cat(nibble, bus[3, 0])
    fill_o <= fill(8, sel)
    signed_sum_w <= a.as_sint + signed_b
    signed_sum_o <= signed_sum_w
    comb_w >= comb_o
    latch_o <= latch_q
    ff_o <= ff_q
    neg_ff_o <= neg_ff_q

    # `always_comb` is the place for procedural combinational selection logic.
    always_comb do
      svif(sel) do
        comb_w <= seed[7, 0]
      end
      svelif(gate) do
        comb_w <= a ^ b
      end
      svelse do
        comb_w <= b
      end
    end

    # `always_latch` emits blocking assignments and is valid for `reg(...)`
    # targets.
    always_latch do
      svif(gate) do
        latch_q <= a
      end
    end

    # One inherited domain can drive several `always_ff` blocks. This keeps
    # repeated sequential logic readable when the clock/reset pair is shared.
    with_clk_and_rst(clk.neg, rst_n.neg)
    always_ff do
      svif(load) do
        ff_q <= bus[7, 0]
      end
      svelse do
        ff_q <= seed[7, 0]
      end
    end

    # The second `always_ff` inherits the same negedge / active-low domain.
    always_ff do
      svif(load) do
        neg_ff_q <= cat(nibble, bus[3, 0])
      end
    end

  end
end

syntax_showcase = SyntaxShowcase.new
output_path = File.join(__dir__, "..", "build", "rtl", "syntax_showcase.sv")

syntax_showcase.to_sv("-")
syntax_showcase.to_sv(output_path)
warn "Written to #{output_path}"
