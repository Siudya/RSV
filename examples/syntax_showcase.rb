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
#   xmake rtl -f syn

$LOAD_PATH.unshift(File.join(__dir__, "..", "lib"))
require "rsv"

class SyntaxShowcase < RSV::ModuleDef
  def build
    let :clk, input(clock)
    let :rst_n, input(reset)
    let :gate, input(bit)
    load = input("load", bit)
    let :sel, input(bit)
    let :pad, inout(bit)
    let :a, input(uint(8))
    let :b, input(uint(8))
    let :signed_b, input(sint(8))
    let :bus, input(uint(16))
    let :nibble, input(bits(4))

    let :sum_o, output(uint(8))
    let :right_assign_o, output(uint(8))
    let :eq_o, output(bit)
    let :ne_o, output(bit)
    let :lt_o, output(bit)
    let :le_o, output(bit)
    let :gt_o, output(bit)
    let :ge_o, output(bit)
    let :logic_and_o, output(bit)
    let :logic_or_o, output(bit)
    let :red_or_o, output(bit)
    let :red_and_o, output(bit)
    let :not_o, output(bit)
    let :pad_sample_o, output(bit)
    let :bit_inv_o, output(uint(8))
    let :shl_o, output(uint(8))
    let :shr_o, output(uint(8))
    let :mul_o, output(uint(8))
    let :div_o, output(uint(8))
    let :mod_o, output(uint(8))
    let :range_o, output(uint(4))
    let :range_alt_o, output(uint(4))
    let :indexed_up_o, output(uint(4))
    let :indexed_down_o, output(uint(4))
    let :mux_o, output(uint(8))
    let :comb_o, output(uint(8))
    let :cat_o, output(uint(8))
    let :fill_o, output(uint(8))
    let :signed_sum_o, output(sint(8))
    let :latch_o, output(uint(8))
    let :ff_o, output(uint(8))
    let :neg_ff_o, output(uint(8))

    # `DataType` values with init data can be combined at Ruby time. Here the
    # result is used as a declaration-time constant, and the generated SV shows
    # the derived width and init value directly.
    runtime_seed_t = uint(8, 5) + uint(8, 2)
    let :seed, wire(uint(runtime_seed_t.width), init: runtime_seed_t.init)

    # `expr(...)` materializes an inferred logic signal while keeping the Ruby
    # expression readable at the call site.
    let :sum_next, expr(a + b)
    let :signed_sum_w, wire(sint(8))
    let :comb_w, wire(uint(8))
    let :latch_q, reg(uint(8))
    let :ff_q, reg(uint(8), init: 0)
    let :neg_ff_q, reg(uint(8), init: 0)

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

RSV::App.main(syntax_showcase)
