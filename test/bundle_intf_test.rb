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
    data  = field("data",  uint(8))
    valid = field("valid", bit)
    ready = field("ready", bit)
    modport "src",  inputs: [ready], outputs: [data, valid]
    modport "sink", inputs: [data, valid], outputs: [ready]
  end
end

class TestBundleStreamIntf < RSV::InterfaceDef
  def build
    payload = field("payload", TestPixel.new)
    valid   = field("valid",   bit)
    ready   = field("ready",   bit)
    modport "src",  inputs: [ready], outputs: [payload, valid]
    modport "sink", inputs: [payload, valid], outputs: [ready]
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
    s = interface_port("stream", TestStreamIntf.new, modport: "sink")
    o = output("data_out", uint(8))
    o <= s.data
  end
end

class BundleIntfPortMod < RSV::ModuleDef
  def build
    s = interface_port("stream", TestBundleStreamIntf.new, modport: "sink")
    o = output("pixel_out", TestPixel.new)
    o <= s.payload
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
    assert_match(/modport src/, sv)
    assert_match(/modport sink/, sv)
    assert_match(/endinterface/, sv)
  end

  def test_interface_port_in_module
    sv = IntfPortMod.new.to_sv
    assert_match(/test_stream_intf\.sink\s+stream/, sv)
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
    assert_match(/test_bundle_stream_intf\.sink\s+stream/, sv)
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
end
