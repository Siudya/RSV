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

# ── Interface test classes ───────────────────────────────────────────────────

class TestStreamIntf < RSV::InterfaceDef
  def build
    data  = output("data",  uint(8))
    valid = output("valid", bit)
    ready = input("ready",  bit)
  end
end

class TestBundleStreamIntf < RSV::InterfaceDef
  def build
    payload = output("payload", TestPixel.new)
    valid   = output("valid",   bit)
    ready   = input("ready",    bit)
  end
end

# Interface with meta-param — different widths produce different SV
class TestParamIntf < RSV::InterfaceDef
  def build(data_w: 8)
    data  = output("data",  uint(data_w))
    valid = output("valid", bit)
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

# Interface accepting bundle type as meta parameter
class TestTemplatedIntf < RSV::InterfaceDef
  def build(payload_t:)
    payload = output("payload", payload_t)
    valid   = output("valid", bit)
    ready   = input("ready", bit)
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

# Module using template interface
class TemplatedIntfMod < RSV::ModuleDef
  def build(intf_dt:, payload_t:)
    s = intf("stream", intf_dt.slv)
    o = output("payload_out", payload_t)
    o <= s.payload
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

class IntfPortMod < RSV::ModuleDef
  def build
    clk = input("clk", clock)
    s = intf("stream", TestStreamIntf.new.slv)
    o = output("data_out", uint(8))
    o <= s.data
  end
end

class BundleIntfPortMod < RSV::ModuleDef
  def build
    s = intf("stream", TestBundleStreamIntf.new.slv)
    o = output("pixel_out", TestPixel.new)
    o <= s.payload
  end
end

# ── Interface interconnect test classes ──────────────────────────────────────

# Whole interface: mst <= slv (mst on left, slv on right)
class IntfConnectMstSlvMod < RSV::ModuleDef
  def build
    m = intf("m_bus", TestStreamIntf.new)          # mst
    s = intf("s_bus", TestStreamIntf.new.slv)      # slv
    m <= s
  end
end

# Whole interface: slv >= mst (slv on left, mst on right via >=)
class IntfConnectSlvGeMstMod < RSV::ModuleDef
  def build
    m = intf("m_bus", TestStreamIntf.new)
    s = intf("s_bus", TestStreamIntf.new.slv)
    s >= m
  end
end

# Individual field assignments on interface ports
class IntfFieldAssignMod < RSV::ModuleDef
  def build
    s = intf("stream", TestStreamIntf.new.slv)
    d_out = output("d_out", uint(8))
    v_out = output("v_out", bit)
    r_in  = input("r_in",  bit)

    d_out <= s.data
    v_out <= s.valid
    s.ready <= r_in
  end
end

# Bad: mst <= mst should fail
class IntfConnectBadMod < RSV::ModuleDef
  def build
    a = intf("a", TestStreamIntf.new)
    b = intf("b", TestStreamIntf.new)
    a <= b
  end
end

# ── Tests ────────────────────────────────────────────────────────────────────

class BundleAndInterfaceTest < Minitest::Test
  # --- Bundle basics ---

  def test_bundle_typedef_emitted
    sv = BundleSimpleMod.new.to_sv
    assert_match(/typedef struct packed/, sv)
    assert_match(/logic \[7:0\] r;/, sv)
    assert_match(/} test_pixel_t;/, sv)
  end

  def test_bundle_port_uses_type_name
    sv = BundleSimpleMod.new.to_sv
    assert_match(/input\s+test_pixel_t\s+px_in/, sv)
    assert_match(/output\s+test_pixel_t\s+px_out/, sv)
  end

  def test_bundle_local_uses_type_name
    sv = BundleSimpleMod.new.to_sv
    assert_match(/test_pixel_t\s+px_r;/, sv)
  end

  def test_bundle_field_access_in_always_ff
    sv = BundleSimpleMod.new.to_sv
    assert_match(/px_r\.r <= px_in\.r;/, sv)
    assert_match(/px_r\.g <= px_in\.g;/, sv)
    assert_match(/px_r\.b <= px_in\.b;/, sv)
  end

  def test_bundle_full_reset
    sv = BundleSimpleMod.new.to_sv
    assert_match(/px_r\.r <= 8'h0;/, sv)
    assert_match(/px_r\.g <= 8'h0;/, sv)
    assert_match(/px_r\.b <= 8'h0;/, sv)
  end

  def test_bundle_partial_reset
    sv = BundlePartialResetMod.new.to_sv
    assert_match(/px_r\.r <= 8'h0;/, sv)
    refute_match(/px_r\.g/, sv.split("if (rst)").last.split("end else").first)
  end

  def test_bundle_nested
    sv = BundleNestedMod.new.to_sv
    assert_match(/test_inner_t/, sv)
    assert_match(/test_outer_t/, sv)
    assert_match(/test_inner_t hdr;/, sv)
    assert_match(/pkt\.data/, sv)
  end

  def test_bundle_mem_array
    sv = BundleMemMod.new.to_sv
    assert_match(/test_pixel_t\s+buf\[7:0\];/, sv)
    assert_match(/buf\[0\]/, sv)
  end

  def test_bundle_sv_param_dedup
    sv = BundleParamMod.new.to_sv
    assert_match(/test_param_pkt_t\b/, sv)
    assert_match(/test_param_pkt_t_1\b/, sv)
    assert_match(/logic \[7:0\] data;/, sv)
    assert_match(/logic \[15:0\] data;/, sv)
  end

  def test_bundle_typedef_ifndef_guard
    sv = BundleSimpleMod.new.to_sv
    assert_match(/`ifndef __RSV_TEST_PIXEL_T_DEFINED__/, sv)
    assert_match(/`define __RSV_TEST_PIXEL_T_DEFINED__/, sv)
    assert_match(/`endif/, sv)
  end

  # --- Interface basics ---

  def test_interface_emits_sv
    dt = TestStreamIntf.new
    intf_def = dt.instance_variable_get(:@_intf_def)
    sv = intf_def.to_sv
    assert_match(/interface test_stream_intf/, sv)
    assert_match(/logic \[7:0\] data;/, sv)
    assert_match(/logic valid;/, sv)
    assert_match(/modport mst/, sv)
    assert_match(/modport slv/, sv)
    assert_match(/endinterface/, sv)
  end

  def test_interface_port_in_module
    sv = IntfPortMod.new.to_sv
    assert_match(/test_stream_intf\.slv\s+stream/, sv)
    assert_match(/stream\.data/, sv)
  end

  def test_interface_with_bundle_field
    dt = TestBundleStreamIntf.new
    intf_def = dt.instance_variable_get(:@_intf_def)
    sv = intf_def.to_sv
    assert_match(/test_pixel_t payload;/, sv)
    assert_match(/typedef struct packed/, sv)
  end

  def test_interface_port_with_bundle
    sv = BundleIntfPortMod.new.to_sv
    assert_match(/test_bundle_stream_intf\.slv\s+stream/, sv)
    assert_match(/stream\.payload/, sv)
  end

  # --- BundleDef class API ---

  def test_bundledef_must_be_subclassed
    assert_raises(ArgumentError) { RSV::BundleDef.new }
  end

  def test_interfacedef_must_be_subclassed
    assert_raises(ArgumentError) { RSV::InterfaceDef.new }
  end

  def test_bundle_returns_data_type
    dt = TestPixel.new
    assert_instance_of RSV::DataType, dt
    assert_equal 24, dt.width  # 3 * 8
    refute_nil dt.bundle_type
  end

  def test_bundle_field_access_handler
    mod = BundleSimpleMod.new
    # Check that the module has a valid locals list
    assert(mod.locals.any? { |l| l.bundle_type })
  end

  # --- Bundle meta-param dedup ---

  def test_bundle_meta_param_dedup
    sv = BundleMetaDedupMod.new.to_sv
    # Two different widths → two distinct typedefs from same base class
    type_names = sv.scan(/test_meta_bundle_t\w*/).uniq
    assert_equal 2, type_names.length, "Expected 2 distinct typedefs, got #{type_names}"
    assert_match(/logic \[7:0\] data;/, sv)
    assert_match(/logic \[31:0\] data;/, sv)
  end

  def test_bundle_same_params_reuse_name
    sv = BundleSameParamMod.new.to_sv
    type_names = sv.scan(/test_meta_bundle_t\w*/).uniq
    assert_equal 1, type_names.length, "Same params should reuse one typedef"
  end

  # --- Interface dedup ---

  def test_interface_meta_param_dedup
    dt8  = TestParamIntf.new(data_w: 8)
    dt16 = TestParamIntf.new(data_w: 16)
    def8  = dt8.instance_variable_get(:@_intf_def)
    def16 = dt16.instance_variable_get(:@_intf_def)
    refute_equal def8.type_name, def16.type_name,
      "Different meta params should produce different type names"
  end

  def test_interface_same_params_reuse_name
    dt_a = TestParamIntf.new(data_w: 64)
    dt_b = TestParamIntf.new(data_w: 64)
    def_a = dt_a.instance_variable_get(:@_intf_def)
    def_b = dt_b.instance_variable_get(:@_intf_def)
    assert_equal def_a.type_name, def_b.type_name,
      "Same meta params should reuse one type name"
  end

  # --- Bundle type as Module/Interface parameter (template) ---

  def test_module_templated_with_bundle_param
    sv = TemplatedMod.new(dat_t: TestPixel.new, init_fields: { "r" => 0 }).to_sv
    assert_match(/typedef struct packed/, sv)
    assert_match(/test_pixel_t/, sv)
    assert_match(/input\s+test_pixel_t\s+d_in/, sv)
    assert_match(/output\s+test_pixel_t\s+d_out/, sv)
    assert_match(/test_pixel_t\s+d_r;/, sv)
    # Partial reset: only r field
    assert_match(/d_r\.r\s*<=/, sv)
  end

  def test_module_templated_different_bundles_produce_different_sv
    sv_px  = TemplatedMod.new(dat_t: TestPixel.new).to_sv
    sv_pkt = TemplatedMod.new(dat_t: TestParamPkt.new).to_sv
    assert_match(/test_pixel_t/, sv_px)
    refute_match(/test_param_pkt_t/, sv_px)
    assert_match(/test_param_pkt_t/, sv_pkt)
    refute_match(/test_pixel_t/, sv_pkt)
  end

  def test_interface_templated_with_bundle_param
    px_t = TestPixel.new
    intf_dt = TestTemplatedIntf.new(payload_t: px_t)
    intf_def = intf_dt.instance_variable_get(:@_intf_def)
    sv = intf_def.to_sv
    assert_match(/typedef struct packed/, sv)
    assert_match(/test_pixel_t payload;/, sv)
    assert_match(/modport mst/, sv)
  end

  def test_module_with_templated_interface_port
    px_t = TestPixel.new
    intf_dt = TestTemplatedIntf.new(payload_t: px_t)
    sv = TemplatedIntfMod.new(intf_dt: intf_dt, payload_t: px_t).to_sv
    assert_match(/test_templated_intf\.slv\s+stream/, sv)
    assert_match(/stream\.payload/, sv)
  end

  # --- Interface interconnect ---

  def test_intf_connect_mst_slv
    sv = IntfConnectMstSlvMod.new.to_sv
    # mst output fields: module drives mst, reads slv
    assert_match(/assign\s+m_bus\.data\s*=\s*s_bus\.data;/, sv)
    assert_match(/assign\s+m_bus\.valid\s*=\s*s_bus\.valid;/, sv)
    # mst input field: module drives slv, reads mst
    assert_match(/assign\s+s_bus\.ready\s*=\s*m_bus\.ready;/, sv)
  end

  def test_intf_connect_slv_ge_mst
    sv = IntfConnectSlvGeMstMod.new.to_sv
    assert_match(/assign\s+m_bus\.data\s*=\s*s_bus\.data;/, sv)
    assert_match(/assign\s+m_bus\.valid\s*=\s*s_bus\.valid;/, sv)
    assert_match(/assign\s+s_bus\.ready\s*=\s*m_bus\.ready;/, sv)
  end

  def test_intf_connect_rejects_same_modport
    assert_raises(ArgumentError) do
      IntfConnectBadMod.new
    end
  end

  def test_intf_field_assign
    sv = IntfFieldAssignMod.new.to_sv
    assert_match(/assign\s+d_out\s*=\s*stream\.data;/, sv)
    assert_match(/assign\s+v_out\s*=\s*stream\.valid;/, sv)
    assert_match(/assign\s+stream\.ready\s*=\s*r_in;/, sv)
  end

  def test_intf_ports_modport_in_sv
    sv = IntfConnectMstSlvMod.new.to_sv
    assert_match(/test_stream_intf\.mst\s+m_bus/, sv)
    assert_match(/test_stream_intf\.slv\s+s_bus/, sv)
  end
end