# frozen_string_literal: true

require "minitest/autorun"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "rsv"

# ── Bundle类型测试 ───────────────────────────────────────────────────────────
# 覆盖: Bundle 基础/嵌套/vec/参数化, iodecl/flip, 模板化, whole assign

# ── Bundle test classes ──────────────────────────────────────────────────────

class TestPixel < RSV::BundleDef
  def build
    r = input("r", uint(8))
    g = input("g", uint(8))
    b = input("b", uint(8))
  end
end

class TestParamPkt < RSV::BundleDef
  def build(w: 8)
    valid = input("valid", bit)
    data  = input("data", uint(w))
  end
end

class TestInner < RSV::BundleDef
  def build
    x = input("x", uint(4))
    y = input("y", uint(4))
  end
end

class TestOuter < RSV::BundleDef
  def build
    hdr  = input("hdr", TestInner.new)
    data = input("data", uint(16))
  end
end

# ── Bundle-as-parameter test classes ─────────────────────────────────────────

class TestMetaBundle < RSV::BundleDef
  def build(w: 8)
    valid = input("valid", bit)
    data  = input("data", uint(w))
  end
end

class TemplatedMod < RSV::ModuleDef
  def build(dat_t:, init_fields: {})
    clk = iodecl("clk", input(clock))
    rst = iodecl("rst", input(reset))
    d_in  = iodecl("d_in", dat_t)
    d_out = iodecl("d_out", flip(dat_t))
    d_r   = reg("d_r", dat_t, init: init_fields.empty? ? nil : init_fields)
    with_clk_and_rst(clk, rst)
    d_out <= d_r
    always_ff { d_r <= d_in }
  end
end

class BundleMetaDedupMod < RSV::ModuleDef
  def build
    w8  = wire("w8",  TestMetaBundle.new(w: 8))
    w32 = wire("w32", TestMetaBundle.new(w: 32))
    o   = iodecl("o", output(uint(8)))
    o <= w8.data
  end
end

class BundleSameParamMod < RSV::ModuleDef
  def build
    w1 = wire("w1", TestMetaBundle.new(w: 16))
    w2 = wire("w2", TestMetaBundle.new(w: 16))
    o  = iodecl("o", output(uint(16)))
    o <= w1.data
  end
end

# ── Module test classes ──────────────────────────────────────────────────────

class BundleSimpleMod < RSV::ModuleDef
  def build
    clk = iodecl("clk", input(clock))
    rst = iodecl("rst", input(reset))
    d = TestPixel.new
    i = iodecl("px_in", d)
    o = iodecl("px_out", flip(d))
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
    clk = iodecl("clk", input(clock))
    rst = iodecl("rst", input(reset))
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
    o = iodecl("data_out", output(uint(16)))
    o <= w.data
  end
end

class BundleMemMod < RSV::ModuleDef
  def build
    d = TestPixel.new
    m = wire("buf", vec(8, d))
    o = iodecl("out", flip(d))
    o <= m[0]
  end
end

class BundleParamMod < RSV::ModuleDef
  def build
    d8 = TestParamPkt.new(w: 8)
    d16 = TestParamPkt.new(w: 16)
    w8 = wire("w8", d8)
    w16 = wire("w16", d16)
    o = iodecl("out8", flip(d8))
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
    assert_match(/logic \[3:0\]\s+pkt_hdr_x;/, sv)
    assert_match(/logic \[3:0\]\s+pkt_hdr_y;/, sv)
    assert_match(/logic \[15:0\]\s+pkt_data;/, sv)
    assert_match(/assign\s+data_out\s*=\s*pkt_data;/, sv)
  end

  def test_bundle_mem_array
    sv = BundleMemMod.new.to_sv
    assert_match(/logic \[7:0\]\s+buf_r\[7:0\];/, sv)
    assert_match(/logic \[7:0\]\s+buf_g\[7:0\];/, sv)
    assert_match(/logic \[7:0\]\s+buf_b\[7:0\];/, sv)
    assert_match(/buf_r\[0\]/, sv)
  end

  def test_bundle_meta_param_dedup
    sv = BundleParamMod.new.to_sv
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

  def test_bundle_meta_param_dedup_different_widths
    sv = BundleMetaDedupMod.new.to_sv
    assert_match(/logic \[7:0\]\s+w8_data;/, sv)
    assert_match(/logic \[31:0\]\s+w32_data;/, sv)
  end

  def test_bundle_same_params_reuse_name
    sv = BundleSameParamMod.new.to_sv
    assert_match(/logic \[15:0\]\s+w1_data;/, sv)
    assert_match(/logic \[15:0\]\s+w2_data;/, sv)
  end

  # --- Bundle type as Module parameter (template) ---

  def test_module_templated_with_bundle_param
    sv = TemplatedMod.new(dat_t: TestPixel.new, init_fields: { "r" => 0 }).to_sv
    assert_match(/input\s+logic \[7:0\]\s+d_in_r/, sv)
    assert_match(/output\s+logic \[7:0\]\s+d_out_r/, sv)
    assert_match(/logic \[7:0\]\s+d_r_r;/, sv)
    assert_match(/d_r_r\s*<=\s*8'h0/, sv)
  end

  def test_module_templated_different_bundles_produce_different_sv
    sv_px  = TemplatedMod.new(dat_t: TestPixel.new).to_sv
    sv_pkt = TemplatedMod.new(dat_t: TestParamPkt.new(w: 8)).to_sv
    assert_match(/d_in_r/, sv_px)
    assert_match(/d_in_g/, sv_px)
    refute_match(/d_in_valid/, sv_px)
    assert_match(/d_in_valid/, sv_pkt)
    assert_match(/d_in_data/, sv_pkt)
    refute_match(/d_in_r/, sv_pkt)
  end

  # --- Whole bundle assignment ---

  def test_bundle_whole_assign_expands_to_per_field
    sv = BundleSimpleMod.new.to_sv
    assert_match(/assign\s+px_out_r\s*=\s*px_r_r;/, sv)
    assert_match(/assign\s+px_out_g\s*=\s*px_r_g;/, sv)
    assert_match(/assign\s+px_out_b\s*=\s*px_r_b;/, sv)
  end

  def test_bundle_mem_indexed_assign_expands
    sv = BundleMemMod.new.to_sv
    assert_match(/assign\s+out_r\s*=\s*buf_r\[0\];/, sv)
    assert_match(/assign\s+out_g\s*=\s*buf_g\[0\];/, sv)
    assert_match(/assign\s+out_b\s*=\s*buf_b\[0\];/, sv)
  end

  # --- iodecl / flip / direction tests ---

  def test_iodecl_with_scalar_output
    mod_class = Class.new(RSV::ModuleDef) do
      define_method(:build) do
        iodecl("io_b", output(uint(24)))
      end
    end
    sv = mod_class.new("TestScalarOut").to_sv
    assert_match(/output\s+logic \[23:0\]\s+io_b/, sv)
  end

  def test_iodecl_with_scalar_input
    mod_class = Class.new(RSV::ModuleDef) do
      define_method(:build) do
        iodecl("io_a", input(uint(8)))
      end
    end
    sv = mod_class.new("TestScalarIn").to_sv
    assert_match(/input\s+logic \[7:0\]\s+io_a/, sv)
  end

  def test_iodecl_with_mem_output
    mod_class = Class.new(RSV::ModuleDef) do
      define_method(:build) do
        iodecl("io_c", output(vec(2, uint(24))))
      end
    end
    sv = mod_class.new("TestMemOut").to_sv
    assert_match(/output\s+logic \[23:0\]\s+io_c\[1:0\]/, sv)
  end

  def test_iodecl_with_bundle_uses_field_dirs
    mod_class = Class.new(RSV::ModuleDef) do
      define_method(:build) do
        pxl_t = TestPixel.new
        iodecl("io_a", pxl_t)
      end
    end
    sv = mod_class.new("TestBundleIO").to_sv
    assert_match(/input\s+logic \[7:0\]\s+io_a_r/, sv)
    assert_match(/input\s+logic \[7:0\]\s+io_a_g/, sv)
    assert_match(/input\s+logic \[7:0\]\s+io_a_b/, sv)
  end

  def test_iodecl_with_flip_reverses_dirs
    mod_class = Class.new(RSV::ModuleDef) do
      define_method(:build) do
        pxl_t = TestPixel.new
        iodecl("io_d", flip(pxl_t))
      end
    end
    sv = mod_class.new("TestFlipIO").to_sv
    assert_match(/output\s+logic \[7:0\]\s+io_d_r/, sv)
    assert_match(/output\s+logic \[7:0\]\s+io_d_g/, sv)
    assert_match(/output\s+logic \[7:0\]\s+io_d_b/, sv)
  end

  def test_iodecl_mixed_dirs_bundle
    mixed_bundle_class = Class.new(RSV::BundleDef) do
      define_singleton_method(:name) { "MixedBundle" }
      define_method(:build) do
        input("ready", bit)
        output("valid", bit)
        output("data", uint(8))
      end
    end

    mod_class = Class.new(RSV::ModuleDef) do
      define_method(:build) do
        iodecl("ch", mixed_bundle_class.new)
      end
    end
    sv = mod_class.new("TestMixedIO").to_sv
    assert_match(/input\s+logic\s+ch_ready/, sv)
    assert_match(/output\s+logic\s+ch_valid/, sv)
    assert_match(/output\s+logic \[7:0\]\s+ch_data/, sv)
  end

  def test_iodecl_flip_mixed_dirs
    mixed_bundle_class = Class.new(RSV::BundleDef) do
      define_singleton_method(:name) { "MixedBundle2" }
      define_method(:build) do
        input("ready", bit)
        output("valid", bit)
        output("data", uint(8))
      end
    end

    mod_class = Class.new(RSV::ModuleDef) do
      define_method(:build) do
        iodecl("ch", flip(mixed_bundle_class.new))
      end
    end
    sv = mod_class.new("TestFlipMixedIO").to_sv
    assert_match(/output\s+logic\s+ch_ready/, sv)
    assert_match(/input\s+logic\s+ch_valid/, sv)
    assert_match(/input\s+logic \[7:0\]\s+ch_data/, sv)
  end

  def test_bundle_as_reg_ignores_direction
    mod_class = Class.new(RSV::ModuleDef) do
      define_method(:build) do
        pxl_t = TestPixel.new
        r = reg("pxl_r", vec(16, pxl_t))
      end
    end
    sv = mod_class.new("TestRegBundle").to_sv
    assert_match(/logic \[7:0\]\s+pxl_r_r\[15:0\];/, sv)
    assert_match(/logic \[7:0\]\s+pxl_r_g\[15:0\];/, sv)
    assert_match(/logic \[7:0\]\s+pxl_r_b\[15:0\];/, sv)
    refute_match(/input.*pxl_r/, sv)
    refute_match(/output.*pxl_r/, sv)
  end

  def test_iodecl_mem_bundle
    mod_class = Class.new(RSV::ModuleDef) do
      define_method(:build) do
        fifo = iodecl("fifo", vec(8, TestPixel.new))
        o = iodecl("o", output(uint(8)))
        o <= fifo[0].r
      end
    end
    sv = mod_class.new("TestMemBundle").to_sv
    assert_match(/input\s+logic \[7:0\]\s+fifo_r\[7:0\]/, sv)
    assert_match(/input\s+logic \[7:0\]\s+fifo_g\[7:0\]/, sv)
    assert_match(/input\s+logic \[7:0\]\s+fifo_b\[7:0\]/, sv)
    assert_match(/assign o = fifo_r\[0\]/, sv)
  end

  def test_iodecl_flip_mem_bundle
    mod_class = Class.new(RSV::ModuleDef) do
      define_method(:build) do
        iodecl("fifo", flip(vec(4, TestPixel.new)))
      end
    end
    sv = mod_class.new("TestFlipMemBundle").to_sv
    assert_match(/output\s+logic \[7:0\]\s+fifo_r\[3:0\]/, sv)
    assert_match(/output\s+logic \[7:0\]\s+fifo_g\[3:0\]/, sv)
    assert_match(/output\s+logic \[7:0\]\s+fifo_b\[3:0\]/, sv)
  end

  def test_iodecl_mem_mixed_dirs_bundle
    mixed_class = Class.new(RSV::BundleDef) do
      define_singleton_method(:name) { "MixedMem" }
      define_method(:build) do
        input("valid", bit)
        output("ready", bit)
        input("data", uint(8))
      end
    end

    mod_class = Class.new(RSV::ModuleDef) do
      define_method(:build) do
        iodecl("ch", vec(2, mixed_class.new))
      end
    end
    sv = mod_class.new("TestMemMixed").to_sv
    assert_match(/input\s+logic\s+ch_valid\[1:0\]/, sv)
    assert_match(/output\s+logic\s+ch_ready\[1:0\]/, sv)
    assert_match(/input\s+logic \[7:0\]\s+ch_data\[1:0\]/, sv)
  end
end
