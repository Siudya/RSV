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
    input :clk, clock
    input :rst, reset

    input :ternary_sel, bit
    input :sel_1h, uint(4)
    input :sel_p, uint(4)
    input :a, uint(8)
    input :b, uint(8)
    input :dats, mem(4, uint(8))

    output :ternary_o, uint(8)
    output :one_hot_o, uint(8)
    output :priority_lsb_o, uint(8)
    output :priority_msb_o, uint(8)

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

    output :res_wire, uint(8)
    res_wire <= res

    reg :res_reg, uint(8), init: 0
    output :res_reg_o, uint(8)
    res_reg_o <= res_reg

    with_clk_and_rst(clk, rst)
    always_ff do
      res_reg <= res
    end

    # ── bundle mux ───────────────────────────────────────────────────
    # mux1h with bundle data: each field gets its own mux case
    input :sel_pxl, uint(2)
    iodecl :pxl_in, input(mem(2, Pixel.new))
    pxl_sel = mux1h(sel_pxl, pxl_in)

    output :pxl_r_o, uint(8)
    output :pxl_g_o, uint(8)
    output :pxl_b_o, uint(8)
    pxl_r_o <= pxl_sel.r
    pxl_g_o <= pxl_sel.g
    pxl_b_o <= pxl_sel.b

    # ── as_uint / get_width ──────────────────────────────────────────
    output :pxl_flat, uint(24)
    pxl_flat <= pxl_sel.as_uint

    input :vec, mem(4, uint(8))
    output :vec_flat, uint(32)
    vec_flat <= vec.as_uint

    # ── cat with bundle and mem ──────────────────────────────────────
    output :cat_out, uint(56)
    cat_out <= cat(pxl_sel, vec)

    # ── mem.reverse ──────────────────────────────────────────────────
    rev = vec.reverse
    output :rev_out, uint(32)
    rev_out <= rev.as_uint

    # bundle mem reverse
    iodecl :bvec, input(mem(2, Pixel.new))
    brev = bvec.reverse
    output :brev_r0, uint(8)
    brev_r0 <= brev[0].r
  end
end

mux_cases = MuxCases.new

RSV::App.main(mux_cases)
