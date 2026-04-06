# frozen_string_literal: true

require "minitest/autorun"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "rsv"

# ── 复合表达式测试 ───────────────────────────────────────────────────────────
# 覆盖: mux/cat/fill, mux1h/muxp (含 bundle), pop_count/log2ceil,
#       as_uint/get_width, as_type 类型转换

class ExpressionTest < Minitest::Test
  # ── mux ternary ────────────────────────────────────────────────────────

  def test_mux_emits_ternary
    mod = module_class("MuxTop") do
      sel = input("sel", bit)
      a = input("a", uint(8))
      b = input("b", uint(8))
      out = output("out", uint(8))

      out <= mux(sel, a, b)
    end.new

    sv = mod.to_sv
    assert_includes sv, "assign out = sel ? a : b;"
  end

  def test_mux_nested
    mod = module_class("MuxNested") do
      s0 = input("s0", bit)
      s1 = input("s1", bit)
      a = input("a", uint(8))
      b = input("b", uint(8))
      c = input("c", uint(8))
      out = output("out", uint(8))

      out <= mux(s0, mux(s1, a, b), c)
    end.new

    sv = mod.to_sv
    assert_includes sv, "assign out = s0 ? (s1 ? a : b) : c;"
  end

  # ── mux1h ──────────────────────────────────────────────────────────────

  def test_mux1h_emits_unique_case
    mod = module_class("Mux1hTop") do
      sel = input("sel", uint(3))
      dats = input("dats", mem([3], uint(8)))
      out = wire("out", uint(8))

      always_comb do
        out <= mux1h(sel, dats)
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "logic [7:0] sel_mux1h_dats"
    assert_includes sv, "always_comb begin"
    assert_includes sv, "unique case (sel)"
    assert_includes sv, "3'h0: sel_mux1h_dats = '0;"
    assert_includes sv, "3'h1: sel_mux1h_dats = dats[0];"
    assert_includes sv, "3'h2: sel_mux1h_dats = dats[1];"
    assert_includes sv, "3'h4: sel_mux1h_dats = dats[2];"
    assert_includes sv, "default: sel_mux1h_dats = 'x;"
    assert_includes sv, "endcase"
    assert_includes sv, "out = sel_mux1h_dats;"
  end

  def test_mux1h_module_level
    mod = module_class("Mux1hMod") do
      sel = input("sel", uint(3))
      dats = input("dats", mem([3], uint(8)))
      out = output("out", uint(8))
      out <= mux1h(sel, dats)
    end.new

    sv = mod.to_sv
    assert_includes sv, "logic [7:0] sel_mux1h_dats"
    assert_includes sv, "unique case (sel)"
    assert_includes sv, "assign out = sel_mux1h_dats;"
  end

  def test_mux1h_wide_sel_hex_format
    mod = module_class("Mux1hWide") do
      sel = input("sel", uint(16))
      dats = input("dats", mem([16], uint(64)))
      out = wire("out", uint(64))

      always_comb do
        out <= mux1h(sel, dats)
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "unique case (sel)"
    assert_includes sv, "16'h0000: sel_mux1h_dats = '0;"
    assert_includes sv, "16'h0001: sel_mux1h_dats = dats[0];"
    assert_includes sv, "16'h0002: sel_mux1h_dats = dats[1];"
    assert_includes sv, "16'h0004: sel_mux1h_dats = dats[2];"
    assert_includes sv, "16'h0008: sel_mux1h_dats = dats[3];"
    assert_includes sv, "16'h8000: sel_mux1h_dats = dats[15];"
    assert_includes sv, "default: sel_mux1h_dats = 'x;"
  end

  # ── muxp ───────────────────────────────────────────────────────────────

  def test_muxp_emits_priority_casez
    mod = module_class("MuxpTop") do
      sel = input("sel", uint(3))
      dats = input("dats", mem([3], uint(8)))
      out = wire("out", uint(8))

      always_comb do
        out <= muxp(sel, dats)
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "logic [7:0] sel_muxp_lo_dats"
    assert_includes sv, "always_comb begin"
    assert_includes sv, "priority casez (sel)"
    assert_includes sv, "3'b??1: sel_muxp_lo_dats = dats[0];"
    assert_includes sv, "3'b?10: sel_muxp_lo_dats = dats[1];"
    assert_includes sv, "3'b100: sel_muxp_lo_dats = dats[2];"
    assert_includes sv, "default: sel_muxp_lo_dats = dats[2];"
    assert_includes sv, "endcase"
    assert_includes sv, "out = sel_muxp_lo_dats;"
  end

  def test_muxp_msb_first
    mod = module_class("MuxpMsb") do
      sel = input("sel", uint(3))
      dats = input("dats", mem([3], uint(8)))
      out = wire("out", uint(8))

      always_comb do
        out <= muxp(sel, dats, lsb_first: false)
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "priority casez (sel)"
    assert_includes sv, "3'b1??: sel_muxp_hi_dats = dats[2];"
    assert_includes sv, "3'b01?: sel_muxp_hi_dats = dats[1];"
    assert_includes sv, "3'b001: sel_muxp_hi_dats = dats[0];"
    assert_includes sv, "default: sel_muxp_hi_dats = dats[0];"
  end

  def test_muxp_module_level
    mod = module_class("MuxpMod") do
      sel = input("sel", uint(3))
      dats = input("dats", mem([3], uint(8)))
      out = output("out", uint(8))
      out <= muxp(sel, dats)
    end.new

    sv = mod.to_sv
    assert_includes sv, "logic [7:0] sel_muxp_lo_dats"
    assert_includes sv, "priority casez (sel)"
    assert_includes sv, "assign out = sel_muxp_lo_dats;"
  end

  # ── eager expansion reuse ──────────────────────────────────────────────

  def test_mux1h_eager_reuse
    mod = module_class("Mux1hReuse") do
      sel = input("sel", uint(3))
      dats = input("dats", mem([3], uint(8)))
      out_a = output("out_a", uint(8))
      out_b = wire("out_b", uint(8))

      res = mux1h(sel, dats)
      out_a <= res

      always_comb do
        out_b <= res
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "assign out_a = sel_mux1h_dats;"
    assert_includes sv, "out_b = sel_mux1h_dats;"
  end

  def test_mux1h_separate_calls_get_separate_wires
    mod = module_class("Mux1hSep") do
      sel = input("sel", uint(3))
      dats = input("dats", mem([3], uint(8)))
      out_a = wire("out_a", uint(8))
      out_b = wire("out_b", uint(8))

      out_a <= mux1h(sel, dats)

      always_comb do
        out_b <= mux1h(sel, dats)
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "sel_mux1h_dats"
    assert_includes sv, "sel_mux1h_dats_1"
  end

  # ── mux1h/muxp with bundle data ───────────────────────────────────────

  def test_mux1h_bundle_data
    pxl_cls = Class.new(RSV::BundleDef) do
      define_singleton_method(:name) { "Pixel" }
      def build
        input("r", uint(8))
        input("g", uint(8))
        input("b", uint(8))
      end
    end

    mod = module_class("Mux1hBundle") do
      sel = input("sel", uint(2))
      dats = wire("dats", mem([2], pxl_cls.new))
      out = wire("out", pxl_cls.new)

      res = mux1h(sel, dats)
      out <= res
    end.new

    sv = mod.to_sv
    assert_includes sv, "logic [7:0] sel_mux1h_dats_r"
    assert_includes sv, "logic [7:0] sel_mux1h_dats_g"
    assert_includes sv, "logic [7:0] sel_mux1h_dats_b"
    assert_includes sv, "unique case (sel)"
    assert_includes sv, "sel_mux1h_dats_r = dats_r[0];"
    assert_includes sv, "sel_mux1h_dats_r = dats_r[1];"
    assert_includes sv, "sel_mux1h_dats_g = dats_g[0];"
    assert_includes sv, "sel_mux1h_dats_b = dats_b[0];"
    assert_includes sv, "assign out_r = sel_mux1h_dats_r;"
    assert_includes sv, "assign out_g = sel_mux1h_dats_g;"
    assert_includes sv, "assign out_b = sel_mux1h_dats_b;"
  end

  def test_muxp_bundle_data
    pxl_cls = Class.new(RSV::BundleDef) do
      define_singleton_method(:name) { "Pixel" }
      def build
        input("r", uint(8))
        input("g", uint(8))
      end
    end

    mod = module_class("MuxpBundle") do
      sel = input("sel", uint(2))
      dats = wire("dats", mem([2], pxl_cls.new))
      out = wire("out", pxl_cls.new)

      res = muxp(sel, dats)
      out <= res
    end.new

    sv = mod.to_sv
    assert_includes sv, "logic [7:0] sel_muxp_lo_dats_r"
    assert_includes sv, "logic [7:0] sel_muxp_lo_dats_g"
    assert_includes sv, "priority casez (sel)"
    assert_includes sv, "assign out_r = sel_muxp_lo_dats_r;"
    assert_includes sv, "assign out_g = sel_muxp_lo_dats_g;"
  end

  # ── as_uint ────────────────────────────────────────────────────────────

  def test_bundle_as_uint
    pxl_cls = pixel_bundle
    mod = module_class("BundleAsUint") do
      pxl = wire("pxl", pxl_cls.new)
      pxl_pack = wire("pxl_pack", uint(pxl.get_width))
      pxl_pack <= pxl.as_uint
    end.new

    sv = mod.to_sv
    assert_includes sv, "logic [23:0] pxl_pack"
    assert_includes sv, "assign pxl_pack = {pxl_r, pxl_g, pxl_b};"
  end

  def test_nested_bundle_as_uint
    pxl_cls = pixel_bundle

    frm_cls = Class.new(RSV::BundleDef) do
      define_singleton_method(:name) { "Frame" }
      define_method(:build) do
        input("pixel", pxl_cls.new)
        input("x_pos", uint(12))
        input("y_pos", uint(12))
        input("last", bit)
      end
    end

    mod = module_class("NestedAsUint") do
      frm = wire("frm", frm_cls.new)
      frm_pack = expr("frm_pack", frm.as_uint)
    end.new

    sv = mod.to_sv
    assert_includes sv, "logic [48:0] frm_pack"
    assert_includes sv, "assign frm_pack = {frm_pixel_r, frm_pixel_g, frm_pixel_b, frm_x_pos, frm_y_pos, frm_last};"
  end

  def test_mem_bundle_as_uint
    pxl_cls = pixel_bundle
    mod = module_class("MemBundleAsUint") do
      pxls = wire("pxls", mem(4, pxl_cls.new))
      pxls_pack = expr("pxls_pack", pxls.as_uint)
    end.new

    sv = mod.to_sv
    assert_includes sv, "logic [95:0] pxls_pack"
    assert_includes sv, "{pxls_r[3], pxls_g[3], pxls_b[3]}"
    assert_includes sv, "{pxls_r[0], pxls_g[0], pxls_b[0]}"
  end

  def test_mem_scalar_as_uint
    mod = module_class("MemScalarAsUint") do
      vals = wire("vals", mem(4, uint(8)))
      packed = expr("packed", vals.as_uint)
    end.new

    sv = mod.to_sv
    assert_includes sv, "logic [31:0] packed"
    assert_includes sv, "assign packed = {vals[3], vals[2], vals[1], vals[0]};"
  end

  def test_bundle_get_width
    pxl_cls = pixel_bundle
    mod = module_class("GetWidth") do
      pxl = wire("pxl", pxl_cls.new)
      pxls = wire("pxls", mem(4, pxl_cls.new))
      wire("w1", uint(pxl.get_width))
      wire("w2", uint(pxls.get_width))
    end.new

    sv = mod.to_sv
    assert_includes sv, "logic [23:0] w1"
    assert_includes sv, "logic [95:0] w2"
  end

  # ── cat ────────────────────────────────────────────────────────────────

  def test_cat_emits_concatenation
    mod = module_class("CatTest") do
      a = input("a", uint(4))
      b = input("b", uint(4))
      c = input("c", uint(8))
      out = output("out", uint(16))
      out <= cat(a, b, c)
    end.new

    sv = mod.to_sv
    assert_includes sv, "assign out = {a, b, c};"
  end

  def test_cat_inside_always_comb
    mod = module_class("CatComb") do
      a = input("a", uint(4))
      b = input("b", uint(4))
      out = wire("out", uint(8))
      always_comb do
        out <= cat(a, b)
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "out = {a, b};"
  end

  def test_cat_bundle_argument
    pxl_cls = pixel_bundle
    mod = module_class("CatBundle") do
      pxl = wire("pxl", pxl_cls.new)
      out = wire("out", uint(24))
      out <= cat(pxl)
    end.new

    sv = mod.to_sv
    assert_includes sv, "assign out = {pxl_r, pxl_g, pxl_b};"
  end

  def test_cat_mem_argument
    mod = module_class("CatMem") do
      vals = wire("vals", mem(4, uint(8)))
      out = wire("out", uint(32))
      out <= cat(vals)
    end.new

    sv = mod.to_sv
    assert_includes sv, "assign out = {vals[3], vals[2], vals[1], vals[0]};"
  end

  def test_cat_mixed_bundle_and_scalar
    pxl_cls = Class.new(RSV::BundleDef) do
      define_singleton_method(:name) { "Pixel" }
      def build
        input("r", uint(8))
        input("g", uint(8))
      end
    end

    mod = module_class("CatMixed") do
      pxl = wire("pxl", pxl_cls.new)
      extra = wire("extra", uint(8))
      out = wire("out", uint(24))
      out <= cat(pxl, extra)
    end.new

    sv = mod.to_sv
    assert_includes sv, "assign out = {pxl_r, pxl_g, extra};"
  end

  # ── fill ───────────────────────────────────────────────────────────────

  def test_fill_emits_replication
    mod = module_class("FillTest") do
      a = input("a", uint(4))
      out = output("out", uint(16))
      out <= fill(4, a)
    end.new

    sv = mod.to_sv
    assert_includes sv, "assign out = {4{a}};"
  end

  def test_fill_inside_always_comb
    mod = module_class("FillComb") do
      a = input("a", uint(1))
      out = wire("out", uint(8))
      always_comb do
        out <= fill(8, a)
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "out = {8{a}};"
  end

  # ── log2ceil ───────────────────────────────────────────────────────────

  def test_log2ceil
    assert_equal 0, RSV.log2ceil(1)
    assert_equal 1, RSV.log2ceil(2)
    assert_equal 2, RSV.log2ceil(3)
    assert_equal 2, RSV.log2ceil(4)
    assert_equal 3, RSV.log2ceil(5)
    assert_equal 3, RSV.log2ceil(8)
    assert_equal 4, RSV.log2ceil(9)
    assert_equal 4, RSV.log2ceil(16)
    assert_equal 5, RSV.log2ceil(17)
    assert_raises(ArgumentError) { RSV.log2ceil(0) }
    assert_raises(ArgumentError) { RSV.log2ceil(-1) }
  end

  def test_log2ceil_in_build
    mod = module_class("Log2CeilMod") do
      w = log2ceil(8 + 1)
      _cnt = wire("cnt", uint(w))
    end.new
    sv = mod.to_sv
    assert_includes sv, "logic [3:0] cnt"
  end

  # ── pop_count ──────────────────────────────────────────────────────────

  def test_pop_count_basic
    mod = module_class("PopCntBasic") do
      vec = input("vec", uint(8))
      cnt = wire("cnt", uint(log2ceil(8 + 1)))

      always_comb do
        cnt <= pop_count(vec)
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "logic [3:0] cnt"
    assert_includes sv, "logic [3:0] vec_pop_count"
    assert_includes sv, "vec_pop_count = 4'd0;"
    assert_includes sv, "for (int _pc_i = 0; _pc_i < 8; _pc_i = _pc_i + 1) begin"
    assert_includes sv, "vec_pop_count = vec_pop_count + {{3{1'b0}}, vec[_pc_i]};"
    assert_includes sv, "cnt = vec_pop_count;"
  end

  def test_pop_count_4bit
    mod = module_class("PopCnt4") do
      vec = input("vec", uint(4))
      cnt = wire("cnt", uint(log2ceil(4 + 1)))

      always_comb do
        cnt <= pop_count(vec)
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "logic [2:0] cnt"
    assert_includes sv, "logic [2:0] vec_pop_count"
    assert_includes sv, "vec_pop_count = 3'd0;"
    assert_includes sv, "for (int _pc_i = 0; _pc_i < 4; _pc_i = _pc_i + 1) begin"
    assert_includes sv, "vec_pop_count = vec_pop_count + {{2{1'b0}}, vec[_pc_i]};"
  end

  def test_pop_count_always_ff
    mod = module_class("PopCntFF") do
      clk = input("clk", clock)
      rst = input("rst", reset)
      vec = input("vec", uint(4))
      cnt = reg("cnt", uint(3), init: 0)

      with_clk_and_rst(clk, rst)
      always_ff do
        cnt <= pop_count(vec)
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "logic [2:0] vec_pop_count"
    assert_includes sv, "vec_pop_count = 3'd0;"
    assert_includes sv, "cnt <= vec_pop_count;"
  end

  def test_pop_count_module_level
    mod = module_class("PopCntTop") do
      vec = input("vec", uint(4))
      cnt = output("cnt", uint(3))
      cnt <= pop_count(vec)
    end.new

    sv = mod.to_sv
    assert_includes sv, "logic [2:0] vec_pop_count"
    assert_includes sv, "vec_pop_count = 3'd0;"
    assert_includes sv, "assign cnt = vec_pop_count;"
  end

  # ── as_type ────────────────────────────────────────────────────────────

  def test_as_type_uint_to_uint_same_width
    mod = module_class("AsTypeSame") do
      a = input("a", uint(8))
      b = wire("b", uint(8))
      b <= a.as_type(uint(8))
    end.new
    sv = mod.to_sv
    assert_includes sv, "assign b = a;"
  end

  def test_as_type_uint_truncate
    mod = module_class("AsTypeTrunc") do
      a = input("a", uint(16))
      b = wire("b", uint(8))
      b <= a.as_type(uint(8))
    end.new
    sv = mod.to_sv
    assert_includes sv, "assign b = a[7:0];"
  end

  def test_as_type_uint_zero_extend
    mod = module_class("AsTypeExtend") do
      a = input("a", uint(8))
      b = wire("b", uint(16))
      b <= a.as_type(uint(16))
    end.new
    sv = mod.to_sv
    assert_includes sv, "assign b = {8'd0, a};"
  end

  def test_as_type_uint_to_sint
    mod = module_class("AsTypeSint") do
      a = input("a", uint(8))
      b = wire("b", sint(8))
      b <= a.as_type(sint(8))
    end.new
    sv = mod.to_sv
    assert_includes sv, "assign b = $signed(a);"
  end

  def test_as_type_bundle_to_uint
    pxl_cls = pixel_bundle
    mod = module_class("BundleToUint") do
      pxl = wire("pxl", pxl_cls.new)
      out = wire("out", uint(24))
      out <= pxl.as_type(uint(24))
    end.new
    sv = mod.to_sv
    assert_includes sv, "assign out = {pxl_r, pxl_g, pxl_b};"
  end

  def test_as_type_uint_to_bundle
    pxl_cls = pixel_bundle
    mod = module_class("UintToBundle") do
      a = input("a", uint(24))
      pxl = a.as_type(pxl_cls.new)
      out_r = wire("out_r", uint(8))
      out_g = wire("out_g", uint(8))
      out_b = wire("out_b", uint(8))
      out_r <= pxl.r
      out_g <= pxl.g
      out_b <= pxl.b
    end.new
    sv = mod.to_sv
    assert_includes sv, "assign a_as_pixel_r = a[23:16];"
    assert_includes sv, "assign a_as_pixel_g = a[15:8];"
    assert_includes sv, "assign a_as_pixel_b = a[7:0];"
  end

  def test_as_type_uint_to_mem
    mod = module_class("UintToMem") do
      a = input("a", uint(32))
      m = a.as_type(mem(4, uint(8)))
      out = wire("out", uint(8))
      out <= m[0]
    end.new
    sv = mod.to_sv
    assert_includes sv, "logic [7:0] a_as_mem[3:0]"
    assert_includes sv, "a_as_mem[0] = a[7:0];"
    assert_includes sv, "a_as_mem[1] = a[15:8];"
    assert_includes sv, "a_as_mem[2] = a[23:16];"
    assert_includes sv, "a_as_mem[3] = a[31:24];"
  end

  def test_as_type_mem_to_uint
    mod = module_class("MemToUint") do
      m = input("m", mem(4, uint(8)))
      out = wire("out", uint(32))
      out <= m.as_type(uint(32))
    end.new
    sv = mod.to_sv
    assert_includes sv, "assign out = {m[3], m[2], m[1], m[0]};"
  end

  def test_as_type_bundle_to_bundle_different
    pair_cls = Class.new(RSV::BundleDef) do
      define_singleton_method(:name) { "Pair" }
      def build
        input("x", uint(12))
        input("y", uint(12))
      end
    end
    pxl_cls = pixel_bundle
    mod = module_class("BundleToBundle") do
      pxl = wire("pxl", pxl_cls.new)
      pair = pxl.as_type(pair_cls.new)
      out_x = wire("out_x", uint(12))
      out_y = wire("out_y", uint(12))
      out_x <= pair.x
      out_y <= pair.y
    end.new
    sv = mod.to_sv
    assert_includes sv, "assign pxl_as_pair_x = {pxl_r, pxl_g, pxl_b}[23:12];"
    assert_includes sv, "assign pxl_as_pair_y = {pxl_r, pxl_g, pxl_b}[11:0];"
  end

  def test_as_type_truncation_uint_to_bundle
    pxl_cls = pixel_bundle
    mod = module_class("TruncToBundle") do
      a = input("a", uint(32))
      pxl = a.as_type(pxl_cls.new)
      out = wire("out", uint(8))
      out <= pxl.r
    end.new
    sv = mod.to_sv
    assert_includes sv, "assign a_as_pixel_r = a[23:0][23:16];"
  end

  def test_as_type_extension_uint_to_bundle
    pxl_cls = pixel_bundle
    mod = module_class("ExtendToBundle") do
      a = input("a", uint(16))
      pxl = a.as_type(pxl_cls.new)
      out = wire("out", uint(8))
      out <= pxl.b
    end.new
    sv = mod.to_sv
    assert_includes sv, "assign a_as_pixel_b = {8'd0, a}[7:0];"
  end

  def test_as_type_uint_to_mem_bundle
    pxl_cls = pixel_bundle
    mod = module_class("UintToMemBundle") do
      a = input("a", uint(48))
      m = a.as_type(mem(2, pxl_cls.new))
      out = wire("out", uint(8))
      out <= m[0].r
    end.new
    sv = mod.to_sv
    assert_match(/a_as_pixel_r/, sv)
    assert_match(/a_as_pixel_g/, sv)
    assert_match(/a_as_pixel_b/, sv)
  end

  private

  def pixel_bundle
    Class.new(RSV::BundleDef) do
      define_singleton_method(:name) { "Pixel" }
      def build
        input("r", uint(8))
        input("g", uint(8))
        input("b", uint(8))
      end
    end
  end

  def module_class(name, &build_block)
    build_block ||= proc {}

    Class.new(RSV::ModuleDef) do
      define_singleton_method(:name) { name }
      define_method(:build, &build_block)
    end
  end
end
