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
    input("r", uint(8))
    input("g", uint(8))
    input("b", uint(8))
  end
end

class MuxCases < ModuleDef
  def build
    clk = input("clk", clock)
    rst = input("rst", reset)

    ternary_sel = input("ternary_sel", bit)
    sel_1h = input("sel_1h", uint(4))
    sel_p = input("sel_p", uint(4))
    a = input("a", uint(8))
    b = input("b", uint(8))
    dats = input("dats", mem(4, uint(8)))

    ternary_o = output("ternary_o", uint(8))
    one_hot_o = output("one_hot_o", uint(8))
    priority_lsb_o = output("priority_lsb_o", uint(8))
    priority_msb_o = output("priority_msb_o", uint(8))

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

    res_wire = output("res_wire", uint(8))
    res_wire <= res

    res_reg = reg("res_reg", uint(8), init: 0)
    res_reg_o = output("res_reg_o", uint(8))
    res_reg_o <= res_reg

    with_clk_and_rst(clk, rst)
    always_ff do
      res_reg <= res
    end

    # ── bundle mux ───────────────────────────────────────────────────
    # mux1h with bundle data: each field gets its own mux case
    sel_pxl = input("sel_pxl", uint(2))
    pxl_in = iodecl("pxl_in", input(mem(2, Pixel.new)))
    pxl_sel = mux1h(sel_pxl, pxl_in)

    pxl_r_o = output("pxl_r_o", uint(8))
    pxl_g_o = output("pxl_g_o", uint(8))
    pxl_b_o = output("pxl_b_o", uint(8))
    pxl_r_o <= pxl_sel.r
    pxl_g_o <= pxl_sel.g
    pxl_b_o <= pxl_sel.b

    # ── as_uint / get_width ──────────────────────────────────────────
    pxl_flat = output("pxl_flat", uint(24))
    pxl_flat <= pxl_sel.as_uint

    vec = input("vec", mem(4, uint(8)))
    vec_flat = output("vec_flat", uint(32))
    vec_flat <= vec.as_uint

    # ── cat with bundle and mem ──────────────────────────────────────
    cat_out = output("cat_out", uint(56))
    cat_out <= cat(pxl_sel, vec)

    # ── mem.reverse ──────────────────────────────────────────────────
    rev = vec.reverse
    rev_out = output("rev_out", uint(32))
    rev_out <= rev.as_uint

    # bundle mem reverse
    bvec = iodecl("bvec", input(mem(2, Pixel.new)))
    brev = bvec.reverse
    brev_r0 = output("brev_r0", uint(8))
    brev_r0 <= brev[0].r
  end
end

mux_cases = MuxCases.new
output_path = File.join(__dir__, "..", "build", "rtl", "mux_cases.sv")

mux_cases.to_sv("-")
mux_cases.to_sv(output_path)
warn "Written to #{output_path}"
