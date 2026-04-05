# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/rsv"

# ── Bundle test classes ──────────────────────────────────────────────────────

class TestPixel < RSV::BundleDef
  def build
    r = field("r", uint(8))
    g = field("g", uint(8))
    b = field("b", uint(8))
  end
end

class TestParamPkt < RSV::BundleDef
  W = sv_param "W", 8
  def build
    valid = field("valid", bit)
    data  = field("data",  uint(W))
  end
end

class TestInner < RSV::BundleDef
  def build
    x = field("x", uint(4))
    y = field("y", uint(4))
  end
end

class TestOuter < RSV::BundleDef
  def build
    hdr  = field("hdr",  TestInner.new)
    data = field("data", uint(16))
  end
end

# ── Bundle-as-parameter test classes ─────────────────────────────────────────

# Bundle meta-param variant (width via meta-param, not sv_param)
class TestMetaBundle < RSV::BundleDef
  def build(w: 8)
    valid = field("valid", bit)
    data  = field("data",  uint(w))
  end
end

# Module accepting bundle type as meta parameter — template-style
class TemplatedMod < RSV::ModuleDef
  def build(dat_t:, init_fields: {})
    clk = input("clk", clock)
    rst = input("rst", reset)
    d_in  = input("d_in", dat_t)
    d_out = output("d_out", dat_t)
    d_r   = reg("d_r", dat_t, init: init_fields.empty? ? nil : init_fields)
    with_clk_and_rst(clk, rst)
    d_out <= d_r
    always_ff { d_r <= d_in }
  end
end

# Modules for dedup tests
class BundleMetaDedupMod < RSV::ModuleDef
  def build
    w8  = wire("w8",  TestMetaBundle.new(w: 8))
    w32 = wire("w32", TestMetaBundle.new(w: 32))
    o   = output("o", uint(8))
    o <= w8.data
  end
end

class BundleSameParamMod < RSV::ModuleDef
  def build
    w1 = wire("w1", TestMetaBundle.new(w: 16))
    w2 = wire("w2", TestMetaBundle.new(w: 16))
    o  = output("o", uint(16))
    o <= w1.data
  end
end

# ── Module test classes ──────────────────────────────────────────────────────

class BundleSimpleMod < RSV::ModuleDef
  def build
    clk = input("clk", clock)
    rst = input("rst", reset)
    d = TestPixel.new
    i = input("px_in", d)
    o = output("px_out", d)
    r = reg("px_r", d, init: { "r" => 0, "g" => 0, "b" => 0 })
    with_clk_and_rst(clk, rst)
    o <= r
    always_ff do
      r.r <= i.r
      r.g <= i.g
      r.b <= i.b
    end
  end
end

class BundlePartialResetMod < RSV::ModuleDef
  def build
    clk = input("clk", clock)
    rst = input("rst", reset)
    d = TestPixel.new
    r = reg("px_r", d, init: { "r" => 0 })
    with_clk_and_rst(clk, rst)
    always_ff { r.r <= 1 }
  end
end

class BundleNestedMod < RSV::ModuleDef
  def build
    d = TestOuter.new
    w = wire("pkt", d)
    o = output("data_out", uint(16))
    o <= w.data
  end
end

class BundleMemMod < RSV::ModuleDef
  def build
    d = TestPixel.new
    m = wire("buf", mem(8, d))
    o = output("out", d)
    o <= m[0]
  end
end

class BundleParamMod < RSV::ModuleDef
  def build
    d8 = TestParamPkt.new
    d16 = TestParamPkt.new.(W: 16)
    w8 = wire("w8", d8)
    w16 = wire("w16", d16)
    o = output("out8", d8)
    o <= w8
  end
end

# ── Tests ────────────────────────────────────────────────────────────────────

class BundleTest < Minitest::Test
  # --- Bundle basics: flat signal emission ---

  def test_bundle_port_emits_flat_signals
    sv = BundleSimpleMod.new.to_sv
    assert_match(/input\s+logic \[7:0\]\s+px_in_r/, sv)
    assert_match(/input\s+logic \[7:0\]\s+px_in_g/, sv)
    assert_match(/input\s+logic \[7:0\]\s+px_in_b/, sv)
    assert_match(/output\s+logic \[7:0\]\s+px_out_r/, sv)
    assert_match(/output\s+logic \[7:0\]\s+px_out_g/, sv)
    assert_match(/output\s+logic \[7:0\]\s+px_out_b/, sv)
  end

  def test_bundle_local_emits_flat_signals
    sv = BundleSimpleMod.new.to_sv
    assert_match(/logic \[7:0\]\s+px_r_r;/, sv)
    assert_match(/logic \[7:0\]\s+px_r_g;/, sv)
    assert_match(/logic \[7:0\]\s+px_r_b;/, sv)
  end

  def test_bundle_field_access_in_always_ff
    sv = BundleSimpleMod.new.to_sv
    assert_match(/px_r_r <= px_in_r;/, sv)
    assert_match(/px_r_g <= px_in_g;/, sv)
    assert_match(/px_r_b <= px_in_b;/, sv)
  end

  def test_bundle_full_reset
    sv = BundleSimpleMod.new.to_sv
    assert_match(/px_r_r <= 8'h0;/, sv)
    assert_match(/px_r_g <= 8'h0;/, sv)
    assert_match(/px_r_b <= 8'h0;/, sv)
  end

  def test_bundle_partial_reset
    sv = BundlePartialResetMod.new.to_sv
    assert_match(/px_r_r <= 8'h0;/, sv)
    reset_block = sv.split("if (rst)").last.split("end else").first
    refute_match(/px_r_g/, reset_block)
    refute_match(/px_r_b/, reset_block)
  end

  def test_bundle_nested
    sv = BundleNestedMod.new.to_sv
    # Nested bundle: TestOuter.hdr (TestInner) → pkt_hdr_x, pkt_hdr_y
    assert_match(/logic \[3:0\]\s+pkt_hdr_x;/, sv)
    assert_match(/logic \[3:0\]\s+pkt_hdr_y;/, sv)
    assert_match(/logic \[15:0\]\s+pkt_data;/, sv)
    assert_match(/assign\s+data_out\s*=\s*pkt_data;/, sv)
  end

  def test_bundle_mem_array
    sv = BundleMemMod.new.to_sv
    # mem(8, Pixel) → buf_r[7:0], buf_g[7:0], buf_b[7:0]
    assert_match(/logic \[7:0\]\s+buf_r\[7:0\];/, sv)
    assert_match(/logic \[7:0\]\s+buf_g\[7:0\];/, sv)
    assert_match(/logic \[7:0\]\s+buf_b\[7:0\];/, sv)
    # Field access: m[0] → buf_r[0], buf_g[0], buf_b[0]
    assert_match(/buf_r\[0\]/, sv)
  end

  def test_bundle_sv_param_dedup
    sv = BundleParamMod.new.to_sv
    # Two different widths → two distinct sets of flat signals
    assert_match(/logic\s+w8_valid;/, sv)
    assert_match(/logic \[7:0\]\s+w8_data;/, sv)
    assert_match(/logic\s+w16_valid;/, sv)
    assert_match(/logic \[15:0\]\s+w16_data;/, sv)
  end

  def test_no_typedef_struct_emitted
    sv = BundleSimpleMod.new.to_sv
    refute_match(/typedef struct packed/, sv)
    refute_match(/`ifndef/, sv)
  end

  # --- BundleDef class API ---

  def test_bundledef_must_be_subclassed
    assert_raises(ArgumentError) { RSV::BundleDef.new }
  end

  def test_bundle_returns_data_type
    dt = TestPixel.new
    assert_instance_of RSV::DataType, dt
    assert_equal 24, dt.width  # 3 * 8
    refute_nil dt.bundle_type
  end

  # --- Bundle meta-param dedup ---

  def test_bundle_meta_param_dedup
    sv = BundleMetaDedupMod.new.to_sv
    # Two different widths produce different flat signal widths
    assert_match(/logic \[7:0\]\s+w8_data;/, sv)
    assert_match(/logic \[31:0\]\s+w32_data;/, sv)
  end

  def test_bundle_same_params_reuse_name
    sv = BundleSameParamMod.new.to_sv
    # Same params → both w1 and w2 have same field structure
    assert_match(/logic \[15:0\]\s+w1_data;/, sv)
    assert_match(/logic \[15:0\]\s+w2_data;/, sv)
  end

  # --- Bundle type as Module parameter (template) ---

  def test_module_templated_with_bundle_param
    sv = TemplatedMod.new(dat_t: TestPixel.new, init_fields: { "r" => 0 }).to_sv
    # Flat signal declarations
    assert_match(/input\s+logic \[7:0\]\s+d_in_r/, sv)
    assert_match(/output\s+logic \[7:0\]\s+d_out_r/, sv)
    assert_match(/logic \[7:0\]\s+d_r_r;/, sv)
    # Partial reset: only r field
    assert_match(/d_r_r\s*<=\s*8'h0/, sv)
  end

  def test_module_templated_different_bundles_produce_different_sv
    sv_px  = TemplatedMod.new(dat_t: TestPixel.new).to_sv
    sv_pkt = TemplatedMod.new(dat_t: TestParamPkt.new).to_sv
    # Pixel has r,g,b fields
    assert_match(/d_in_r/, sv_px)
    assert_match(/d_in_g/, sv_px)
    refute_match(/d_in_valid/, sv_px)
    # Packet has valid,data fields
    assert_match(/d_in_valid/, sv_pkt)
    assert_match(/d_in_data/, sv_pkt)
    refute_match(/d_in_r/, sv_pkt)
  end

  # --- Whole bundle assignment ---

  def test_bundle_whole_assign_expands_to_per_field
    sv = BundleSimpleMod.new.to_sv
    # o <= r becomes per-field assigns
    assert_match(/assign\s+px_out_r\s*=\s*px_r_r;/, sv)
    assert_match(/assign\s+px_out_g\s*=\s*px_r_g;/, sv)
    assert_match(/assign\s+px_out_b\s*=\s*px_r_b;/, sv)
  end

  def test_bundle_mem_indexed_assign_expands
    sv = BundleMemMod.new.to_sv
    # o <= m[0] → out_r <= buf_r[0], etc.
    assert_match(/assign\s+out_r\s*=\s*buf_r\[0\];/, sv)
    assert_match(/assign\s+out_g\s*=\s*buf_g\[0\];/, sv)
    assert_match(/assign\s+out_b\s*=\s*buf_b\[0\];/, sv)
  end
end
