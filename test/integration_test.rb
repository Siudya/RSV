# frozen_string_literal: true

require "minitest/autorun"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "rsv"

# ── 集成测试 ─────────────────────────────────────────────────────────────────
# 覆盖: sv_plugin, v_wrapper (scalar/unpacked/bundle/custom), import_sv

class WrapTestPixelInteg < RSV::BundleDef
  def build
    input("r", uint(8))
    input("g", uint(8))
    input("b", uint(8))
  end
end

class MetaParamIntegModule < RSV::ModuleDef
  def build(width: 8)
    input("d", uint(width))
    output("q", uint(width))
  end
end

class MetaParamIntegExprModule < RSV::ModuleDef
  def build(n: 4)
    a = input("a", uint(n))
    y = output("y", uint(n))
    y <= a + n
  end
end

class IntegrationTest < Minitest::Test
  # ── sv_plugin ──────────────────────────────────────────────────────────

  def test_sv_plugin_module_level
    klass = module_class("PluginMod") do
      input("a", uint(8))
      sv_plugin "// custom comment"
      sv_plugin "assign foo = bar;"
    end
    mod = klass.new("plugin_mod")
    sv = mod.to_sv
    assert_includes sv, "  // custom comment"
    assert_includes sv, "  assign foo = bar;"
  end

  def test_sv_plugin_multiline
    klass = module_class("PluginMulti") do
      input("clk", clock)
      sv_plugin "always @(posedge clk) begin\n  $display(\"hello\");\nend"
    end
    mod = klass.new("plugin_multi")
    sv = mod.to_sv
    assert_includes sv, "  always @(posedge clk) begin"
    assert_includes sv, "    $display(\"hello\");"
    assert_includes sv, "  end"
  end

  def test_sv_plugin_inside_always_ff
    klass = module_class("PluginProc") do
      clk = input("clk", clock)
      rst = input("rst", reset)
      a = input("a", uint(8))
      r = reg("r", uint(8), init: 0)
      with_clk_and_rst(clk, rst)
      always_ff do
        sv_plugin '$display("r=%h", r);'
        r <= a
      end
    end
    mod = klass.new("plugin_proc")
    sv = mod.to_sv
    assert_includes sv, '$display("r=%h", r);'
  end

  # ── v_wrapper ──────────────────────────────────────────────────────────

  def test_v_wrapper_scalar_ports
    klass = module_class("WrapScalar") do
      a = input("a", uint(8))
      b = output("b", uint(8))
      b <= a
    end
    mod = klass.new("wrap_scalar")
    wrapper = mod.v_wrapper
    assert_includes wrapper, "module wrap_scalar_wrapper"
    assert_includes wrapper, "input  [   7:0] a"
    assert_includes wrapper, "output [   7:0] b"
    assert_includes wrapper, ".a(a)"
    assert_includes wrapper, ".b(b)"
    refute_includes wrapper, "_sv"
  end

  def test_v_wrapper_unpacked_array
    klass = module_class("WrapUnpacked") do
      m = input("mem_in", mem(3, uint(16)))
      r = output("result", uint(16))
      r <= m[0]
    end
    mod = klass.new("wrap_unpacked")
    wrapper = mod.v_wrapper
    assert_includes wrapper, "mem_in_0"
    assert_includes wrapper, "mem_in_1"
    assert_includes wrapper, "mem_in_2"
    assert_includes wrapper, "mem_in_sv [0:2]"
    assert_includes wrapper, "assign mem_in_sv[0] = mem_in_0;"
    assert_includes wrapper, ".mem_in(mem_in_sv)"
  end

  def test_v_wrapper_custom_name
    klass = module_class("WrapCustom") do
      x = input("x", uint(1))
      y = output("y", uint(1))
      y <= x
    end
    mod = klass.new("wrap_custom")
    wrapper = mod.v_wrapper(wrapper_name: "my_top")
    assert_includes wrapper, "module my_top ("
  end

  def test_v_wrapper_bundle_port
    klass = module_class("WrapBundle") do
      p_in = iodecl("px", WrapTestPixelInteg.new)
      p_out = iodecl("px_out", flip(WrapTestPixelInteg.new))
      p_out <= p_in
    end
    mod = klass.new("wrap_bundle")
    wrapper = mod.v_wrapper
    assert_includes wrapper, "input  [   7:0] px_r"
    assert_includes wrapper, "input  [   7:0] px_g"
    assert_includes wrapper, "input  [   7:0] px_b"
    assert_includes wrapper, "output [   7:0] px_out_r"
    assert_includes wrapper, "output [   7:0] px_out_g"
    assert_includes wrapper, "output [   7:0] px_out_b"
    assert_includes wrapper, ".px_r(px_r)"
    assert_includes wrapper, ".px_out_r(px_out_r)"
  end

  def test_v_wrapper_mem_bundle_port
    klass = module_class("WrapMemBundle") do
      fifo_in = iodecl("fifo", WrapTestPixelInteg.new)
      fifo_in_mem = input("fifo_extra", mem(2, uint(8)))
      o = output("o", uint(8))
      o <= fifo_in.r
    end
    mod = klass.new("wrap_mem_bundle")
    wrapper = mod.v_wrapper
    assert_includes wrapper, "fifo_r"
    assert_includes wrapper, "fifo_g"
    assert_includes wrapper, "fifo_b"
  end

  # ── meta_param ─────────────────────────────────────────────────────────

  def test_meta_param_declares_no_parameter
    mod = MetaParamIntegModule.new("meta_param_test", width: 8)
    sv = mod.to_sv
    refute_includes sv, "parameter"
    assert_includes sv, "[7:0]"
  end

  def test_meta_param_override
    mod = MetaParamIntegModule.new("meta_param_override", width: 32)
    sv = mod.to_sv
    assert_includes sv, "[31:0]"
    refute_includes sv, "parameter"
  end

  def test_meta_param_in_expression
    mod = MetaParamIntegExprModule.new("meta_param_expr", n: 4)
    sv = mod.to_sv
    assert_includes sv, "assign y = a + 4'd4;"
  end

  def test_meta_params_different_widths
    unsigned_mod = MetaParamIntegModule.new("meta_u", width: 8)
    sv = unsigned_mod.to_sv
    assert_includes sv, "[7:0]"

    wide_mod = MetaParamIntegModule.new("meta_w", width: 16)
    sv = wide_mod.to_sv
    assert_includes sv, "[15:0]"
  end

  # ── import_sv ──────────────────────────────────────────────────────────

  FIXTURE_DIR = File.expand_path("fixtures/svimport", __dir__)
  IMPORTED_COUNTER = File.join(FIXTURE_DIR, "imported_counter.sv")

  def test_import_sv_extracts_module_signature_via_pyslang
    imported = RSV.import_sv(IMPORTED_COUNTER, top: "ImportedCounter", incdirs: [FIXTURE_DIR])
    definition = imported.build_definition

    assert_equal "ImportedCounter", imported.name
    assert_equal "ImportedCounter", definition.name
    assert_equal [
      ["WIDTH", "12", "int", "12"],
      ["DEPTH", "24", "int", "WIDTH * 2"]
    ], definition.params.map { |param| [param.name, param.value, param.param_type, param.raw_default] }
    assert_equal [
      ["clk", :input, "logic"],
      ["rst_n", :input, "logic"],
      ["din", :input, "logic [WIDTH-1:0]"],
      ["dout", :output, "logic [WIDTH-1:0]"],
      ["mem", :output, "logic [7:0] [4]"]
    ], definition.ports.map { |port| [port.name, port.dir, port.raw_type] }
  end

  def test_imported_sv_module_can_be_instantiated_inside_rsv_module
    imported = RSV.import_sv(IMPORTED_COUNTER, top: "ImportedCounter", incdirs: [FIXTURE_DIR])

    top = Class.new(RSV::ModuleDef) do
      define_singleton_method(:name) { "ImportedTop" }

      define_method(:build) do
        clk = input("clk", bit)
        rst_n = input("rst_n", bit)
        din = input("din", uint(12))
        dout = output("dout", uint(12))

        counter = imported.new(inst_name: "u_counter", WIDTH: 16)
        counter.clk <= clk
        counter.rst_n <= rst_n
        counter.din <= din
        dout <= counter.dout
      end
    end.new

    expected = <<~SV.chomp
      module ImportedTop (
        input  logic        clk,
        input  logic        rst_n,
        input  logic [11:0] din,
        output logic [11:0] dout
      );

        ImportedCounter #(
          .WIDTH(16),
          .DEPTH(32)
        ) u_counter (
          .clk(clk),
          .rst_n(rst_n),
          .din(din),
          .dout(dout)
        );

      endmodule
    SV

    assert_equal expected, top.to_sv
  end

  def test_imported_definition_handle_can_be_instantiated_manually
    imported = RSV.import_sv(IMPORTED_COUNTER, top: "ImportedCounter", incdirs: [FIXTURE_DIR])
    imported_def = imported.definition(WIDTH: 16)

    top = Class.new(RSV::ModuleDef) do
      define_singleton_method(:name) { "ImportedTop" }

      define_method(:build) do |imported_def:|
        clk = input("clk", bit)
        rst_n = input("rst_n", bit)
        din = input("din", uint(12))
        dout = output("dout", uint(12))

        counter = instance(imported_def, inst_name: "u_counter")
        counter.clk <= clk
        counter.rst_n <= rst_n
        counter.din <= din
        dout <= counter.dout
      end
    end.new(imported_def: imported_def)

    expected = <<~SV.chomp
      module ImportedTop (
        input  logic        clk,
        input  logic        rst_n,
        input  logic [11:0] din,
        output logic [11:0] dout
      );

        ImportedCounter #(
          .WIDTH(16),
          .DEPTH(32)
        ) u_counter (
          .clk(clk),
          .rst_n(rst_n),
          .din(din),
          .dout(dout)
        );

      endmodule
    SV

    assert_equal "ImportedCounter", imported_def.module_name
    assert_equal expected, top.to_sv
  end

  private

  def module_class(name, &build_block)
    build_block ||= proc {}

    Class.new(RSV::ModuleDef) do
      define_singleton_method(:name) { name }
      define_method(:build, &build_block)
    end
  end
end
