# frozen_string_literal: true
# examples/mux_cases.rb
#
# Demonstrates mux helpers and related bundle/mem operations:
# - `mux(...)` for a plain ternary expression
# - `mux1h(...)` for a one-hot case tree (scalar and bundle data)
# - `muxp(...)` for a priority casez tree in both LSB-first and MSB-first modes
# - module-level mux (eager expansion, wire reuse across assign/always)
# - `as_uint` / `get_width` for bundles and mems
# - `cat(bundle, mem)` mixed concatenation
# - `mem.reverse` for reversing element order
#
# Run:
#   xmake rtl -f mux

$LOAD_PATH.unshift(File.join(__dir__, "..", "lib"))
require "rsv"
include RSV

class Pixel < BundleDef
  def build
    input :r, uint(8)
    input :g, uint(8)
    input :b, uint(8)
  end
end

class MuxCases < ModuleDef
  def build
    let :clk, input(clock)
    let :rst, input(reset)

    let :ternary_sel, input(bit)
    let :sel_1h, input(uint(4))
    let :sel_p, input(uint(4))
    let :a, input(uint(8))
    let :b, input(uint(8))
    let :dats, input(mem(4, uint(8)))

    let :ternary_o, output(uint(8))
    let :one_hot_o, output(uint(8))
    let :priority_lsb_o, output(uint(8))
    let :priority_msb_o, output(uint(8))

    # ── basic mux ────────────────────────────────────────────────────
    ternary_o <= mux(ternary_sel, a, b)

    always_comb do
      one_hot_o <= mux1h(sel_1h, dats)
      priority_lsb_o <= muxp(sel_p, dats)
      priority_msb_o <= muxp(sel_p, dats, lsb_first: false)
    end

    # ── module-level mux reuse ───────────────────────────────────────
    # mux1h at module level creates a wire; reusable in assign and always_ff
    res = mux1h(sel_1h, dats)

    let :res_wire, output(uint(8))
    res_wire <= res

    let :res_reg, reg(uint(8), init: 0)
    let :res_reg_o, output(uint(8))
    res_reg_o <= res_reg

    with_clk_and_rst(clk, rst)
    always_ff do
      res_reg <= res
    end

    # ── bundle mux ───────────────────────────────────────────────────
    # mux1h with bundle data: each field gets its own mux case
    let :sel_pxl, input(uint(2))
    let :pxl_in, input(mem(2, Pixel.new))
    pxl_sel = mux1h(sel_pxl, pxl_in)

    let :pxl_r_o, output(uint(8))
    let :pxl_g_o, output(uint(8))
    let :pxl_b_o, output(uint(8))
    pxl_r_o <= pxl_sel.r
    pxl_g_o <= pxl_sel.g
    pxl_b_o <= pxl_sel.b

    # ── as_uint / get_width ──────────────────────────────────────────
    let :pxl_flat, output(uint(24))
    pxl_flat <= pxl_sel.as_uint

    let :vec, input(mem(4, uint(8)))
    let :vec_flat, output(uint(32))
    vec_flat <= vec.as_uint

    # ── cat with bundle and mem ──────────────────────────────────────
    let :cat_out, output(uint(56))
    cat_out <= cat(pxl_sel, vec)

    # ── mem.reverse ──────────────────────────────────────────────────
    rev = vec.reverse
    let :rev_out, output(uint(32))
    rev_out <= rev.as_uint

    # bundle mem reverse
    let :bvec, input(mem(2, Pixel.new))
    brev = bvec.reverse
    let :brev_r0, output(uint(8))
    brev_r0 <= brev[0].r
  end
end

mux_cases = MuxCases.new

RSV::App.main(mux_cases)
