# frozen_string_literal: true

require "minitest/autorun"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "rsv"

# Test helper classes for v_wrapper bundle tests
class WrapTestPixel < RSV::BundleDef
  def build
    input("r", uint(8))
    input("g", uint(8))
    input("b", uint(8))
  end
end

# Test helper classes for meta-param module tests
class MetaParamTestModule < RSV::ModuleDef
  def build(width: 8)
    input("d", uint(width))
    output("q", uint(width))
  end
end

class MetaParamExprModule < RSV::ModuleDef
  def build(n: 4)
    a = input("a", uint(n))
    y = output("y", uint(n))
    y <= a + n
  end
end

class HandlerDslTest < Minitest::Test
  def test_module_def_public_api_uses_snake_case
    mod = module_class("SnakeApi").new

    assert_respond_to mod, :with_clk_and_rst
    assert_respond_to mod, :always_ff
    assert_respond_to mod, :always_comb
    assert_respond_to mod, :always_latch
    assert_respond_to mod, :to_sv
    assert_respond_to mod, :wire
    assert_respond_to mod, :reg
    assert_respond_to mod, :bit
    assert_respond_to mod, :uint
    assert_respond_to mod, :bits
    assert_respond_to mod, :sint
    assert_respond_to mod, :clock
    assert_respond_to mod, :reset
    assert_respond_to mod, :mem
    assert_respond_to mod, :mux
    assert_respond_to mod, :mux1h
    assert_respond_to mod, :muxp
    assert_respond_to mod, :cat
    assert_respond_to mod, :fill
    assert_respond_to mod, :definition
    assert_respond_to mod, :instance

    refute_respond_to mod, :instantiate
    refute_respond_to mod, :assign_stmt
    refute_respond_to mod, :logic
    refute_respond_to mod, :assignStmt
    refute_respond_to mod, :withClkAndRst
    refute_respond_to mod, :alwaysFf
    refute_respond_to mod, :alwaysComb
    refute_respond_to mod, :alwaysLatch
    refute_respond_to mod, :toSv
  end

  def test_handler_signals_emit_wire_and_logic_declarations
    mod = module_class("Counter") do
      clk = input("clk", clock)
      rst_n = input("rst_n", reset)
      count = output("count", uint(16))
      seed = wire("seed", uint(16), init: 0x7)
      count_r = reg("count_r", uint(16), init: 0)

      count <= count_r

      with_clk_and_rst(clk, rst_n.neg)
      always_ff do
        svif(1) do
          count_r <= seed
        end
      end
    end.new

    expected = <<~SV.chomp
      module Counter (
        input  logic        clk,
        input  logic        rst_n,
        output logic [15:0] count
      );

        logic [15:0] seed    = 16'h7;
        logic [15:0] count_r;

        assign count = count_r;

        always_ff @(posedge clk or negedge rst_n) begin
          if (!rst_n) begin
            count_r <= 16'h0;
          end else if (1) begin
            count_r <= seed;
          end
        end

      endmodule
    SV

    assert_equal expected, mod.to_sv
  end

  def test_string_based_always_ff_is_removed
    error = assert_raises(ArgumentError) do
      module_class("NoStringAlwaysFf") do
        clk = input("clk", bit)
        rst_n = input("rst_n", bit)
        value = reg("value", uint(8))

        always_ff("posedge #{clk} or negedge #{rst_n}") do
          value <= 0
        end
      end.new
    end

    assert_equal "always_ff expects no arguments or explicit clock/reset", error.message
  end

  def test_handlers_can_be_used_in_instance_connections
    counter_class = module_class("Counter") do
      clk = input("clk", bit)
      count = output("count", uint(16))
    end

    mod = Class.new(RSV::ModuleDef) do
      define_singleton_method(:name) { "Top" }

      define_method(:build) do
        clk = input("clk", bit)
        count = wire("count", uint(16))

        counter = counter_class.new(inst_name: "u_counter")
        counter.clk <= clk
        count <= counter.count
      end
    end.new

    sv = mod.to_sv

    assert_includes sv, "Counter u_counter ("
    assert_includes sv, ".clk(clk)"
    assert_includes sv, ".count(count)"
  end

    def test_local_declarations_are_aligned
      mod = module_class("AlignedDecls") do
      wire("a", bit)
      reg("count_r", uint(16))
      wire("seed", uint(16), init: 0x7)
      end.new

    expected = <<~SV.chomp
      module AlignedDecls (
      );

        logic        a;
        logic [15:0] count_r;
        logic [15:0] seed    = 16'h7;

      endmodule
    SV

    assert_equal expected, mod.to_sv
  end

  def test_const_emits_localparam
    mod = module_class("ConstTest") do
      a = const("MAGIC", sint(16, 0x57))
      b = const("THRESHOLD", uint(8, 42))
      out = output("out", sint(16))
      out <= a
    end.new

    sv = mod.to_sv
    assert_includes sv, "localparam signed [15:0] MAGIC"
    assert_includes sv, "16'h57"
    assert_includes sv, "localparam"
    assert_includes sv, "THRESHOLD"
    assert_includes sv, "8'h2a"
    assert_includes sv, "assign out = MAGIC;"
  end

  def test_const_requires_init_value
    error = assert_raises(ArgumentError) do
      module_class("ConstNoInit") do
        const("BAD", uint(8))
      end.new
    end

    assert_includes error.message, "const requires an init value"
  end

  def test_const_cannot_be_assigned
    error = assert_raises(ArgumentError) do
      module_class("ConstAssign") do
        a = const("RO", uint(8, 1))
        b = wire("w", uint(8))
        b <= a
        a <= b
      end.new.to_sv
    end

    assert_includes error.message, "const signal RO cannot be assigned"
  end

  def test_attr_on_port
    mod = module_class("AttrPort") do
      input("clk", bit, attr: { "mark_debug" => "\"true\"" })
      output("dout", uint(8), attr: { "keep" => nil })
    end.new

    sv = mod.to_sv
    assert_includes sv, "(* mark_debug = \"true\" *)\n  input"
    assert_includes sv, "(* keep *)\n  output"
  end

  def test_attr_on_local
    mod = module_class("AttrLocal") do
      wire("dbg_sig", uint(8), attr: { "mark_debug" => "\"true\"" })
      reg("keep_reg", uint(4), attr: { "dont_touch" => nil, "keep" => nil })
    end.new

    sv = mod.to_sv
    assert_includes sv, "(* mark_debug = \"true\" *)\n  logic"
    assert_includes sv, "(* dont_touch, keep *)\n  logic"
  end

  def test_attr_on_const
    mod = module_class("AttrConst") do
      const("MY_CONST", uint(8, 0xFF), attr: { "synthesis" => "\"off\"" })
    end.new

    sv = mod.to_sv
    assert_includes sv, "(* synthesis = \"off\" *)\n  localparam"
  end

  def test_continuous_assigns_align_equals
    mod = module_class("AlignedAssigns") do
      a = input("a", uint(8))
      short = wire("x", uint(8))
      long_name = wire("long_name", uint(8))
      y = output("y", uint(8))

      short <= a
      long_name <= short
      y <= long_name
    end.new

    expected = <<~SV.chomp
      module AlignedAssigns (
        input  logic [7:0] a,
        output logic [7:0] y
      );

        logic [7:0] x;
        logic [7:0] long_name;

        assign x         = a;
        assign long_name = x;
        assign y         = long_name;

      endmodule
    SV

    assert_equal expected, mod.to_sv
  end

  def test_sv_def_emits_define
    mod = module_class("DefTest") do
      sv_def "MY_MACRO", "42"
      sv_def "FLAG"
      output("dout", uint(8))
    end.new

    sv = mod.to_sv
    assert_includes sv, "`define MY_MACRO 42"
    assert_includes sv, "`define FLAG"
    refute_includes sv, "`define FLAG "
  end

  def test_sv_undef_emits_undef
    mod = module_class("UndefTest") do
      sv_def "TMP", "1"
      sv_undef "TMP"
    end.new

    sv = mod.to_sv
    assert_includes sv, "`undef TMP"
  end

  def test_sv_ifdef_endif
    mod = module_class("IfdefTest") do
      out = output("out", uint(8))
      w = wire("w", uint(8))
      sv_ifdef("SIM") do
        out <= w
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "`ifdef SIM"
    assert_includes sv, "assign out = w;"
    assert_includes sv, "`endif"
  end

  def test_sv_ifdef_else
    mod = module_class("IfdefElseTest") do
      out = output("out", uint(8))
      a = wire("a", uint(8))
      b = wire("b", uint(8))
      sv_ifdef("SIM") do
        out <= a
      end.sv_else_def do
        out <= b
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "`ifdef SIM"
    assert_includes sv, "assign out = a;"
    assert_includes sv, "`else"
    assert_includes sv, "assign out = b;"
    assert_includes sv, "`endif"
  end

  def test_sv_ifndef_with_elif
    mod = module_class("IfndefElifTest") do
      out = output("out", uint(8))
      a = wire("a", uint(8))
      b = wire("b", uint(8))
      c = wire("c", uint(8))
      sv_ifndef("SYNTHESIS") do
        out <= a
      end.sv_elif_def("FPGA") do
        out <= b
      end.sv_else_def do
        out <= c
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "`ifndef SYNTHESIS"
    assert_includes sv, "`elsif FPGA"
    assert_includes sv, "`else"
    assert_includes sv, "`endif"
  end

  def test_sv_dref_macro_reference
    mod = module_class("DrefTest") do
      sv_def "WIDTH", "8"
      out = output("out", uint(8))
      w = wire("w", uint(8))
      out <= w + sv_dref("WIDTH")
    end.new

    sv = mod.to_sv
    assert_includes sv, "`define WIDTH 8"
    assert_includes sv, "`WIDTH"
  end

  # ── Generate tests ──────────────────────────────────────────────────────

  def test_generate_for_with_local_and_always
    mod = module_class("GenForTest") {
      clk = input("clk", clock)
      rst = input("rst", reset)
      d = input("d", mem(4, uint(8)))
      q = output("q", mem(4, uint(8)))
      with_clk_and_rst(clk, rst)
      generate_for("i", 0, 4, label: "gen_pipe") do |i|
        r = reg("r", uint(8))
        always_ff { r <= d[i] }
        q[i] <= r
      end
    }.new

    sv = mod.to_sv
    assert_includes sv, "for (genvar i = 0; i < 4; i = i + 1) begin : gen_pipe"
    assert_includes sv, "logic [7:0] r;"
    assert_includes sv, "always_ff"
    assert_includes sv, "r <= d[i];"
    assert_includes sv, "assign q[i] = r;"
    assert_includes sv, "end"
  end

  def test_generate_if_with_elsif_and_else
    mod = module_class("GenIfTest") {
      mode = const("MODE", uint(2, 1))
      a = input("a", uint(8))
      y = output("y", uint(8))
      generate_if(mode.eq(0), label: "m0") {
        y <= 0
      }.generate_elif(mode.eq(1), label: "m1") {
        y <= a
      }.generate_else(label: "mdef") {
        y <= 0xff
      }
    }.new

    sv = mod.to_sv
    assert_includes sv, "if (MODE == 0) begin : m0"
    assert_includes sv, "end else if (MODE == 1) begin : m1"
    assert_includes sv, "end else begin : mdef"
    assert_includes sv, "assign y = 8'd255;"
  end

  def test_generate_for_without_label
    mod = module_class("GenForNoLabel") {
      d = input("d", mem(2, uint(4)))
      q = output("q", mem(2, uint(4)))
      generate_for("j", 0, 2) do |j|
        q[j] <= d[j]
      end
    }.new

    sv = mod.to_sv
    assert_includes sv, "for (genvar j = 0; j < 2; j = j + 1) begin"
    refute_includes sv, "begin :"
  end

  def test_generate_if_only_then
    mod = module_class("GenIfOnly") {
      en = const("EN", uint(1, 1))
      a = input("a", uint(8))
      y = output("y", uint(8))
      generate_if(en.eq(1), label: "gen_en") {
        y <= a
      }
    }.new

    sv = mod.to_sv
    assert_includes sv, "if (EN == 1) begin : gen_en"
    assert_includes sv, "assign y = a;"
    refute_includes sv, "else"
  end

  # ── Meta parameter tests ─────────────────────────────────────────────

  def test_meta_param_declares_no_parameter
    mod = MetaParamTestModule.new("meta_param_test", width: 8)
    sv = mod.to_sv
    refute_includes sv, "parameter"
    assert_includes sv, "[7:0]"
  end

  def test_meta_param_override
    mod = MetaParamTestModule.new("meta_param_override", width: 32)
    sv = mod.to_sv
    assert_includes sv, "[31:0]"
    refute_includes sv, "parameter"
  end

  def test_meta_param_in_expression
    mod = MetaParamExprModule.new("meta_param_expr", n: 4)
    sv = mod.to_sv
    assert_includes sv, "assign y = a + 4'd4;"
  end

  def test_meta_params_different_widths
    unsigned_mod = MetaParamTestModule.new("meta_u", width: 8)
    sv = unsigned_mod.to_sv
    assert_includes sv, "[7:0]"

    wide_mod = MetaParamTestModule.new("meta_w", width: 16)
    sv = wide_mod.to_sv
    assert_includes sv, "[15:0]"
  end

  # --- Task 6: Verilog wrapper ---

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

  # --- sv_plugin tests ---

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

  # --- v_wrapper interface/bundle tests ---

  def test_v_wrapper_bundle_port
    klass = module_class("WrapBundle") do
      p_in = iodecl("px", WrapTestPixel.new)
      p_out = iodecl("px_out", flip(WrapTestPixel.new))
      p_out <= p_in
    end
    mod = klass.new("wrap_bundle")
    wrapper = mod.v_wrapper
    # Bundle ports already flat — direct mapping
    assert_includes wrapper, "input  [   7:0] px_r"
    assert_includes wrapper, "input  [   7:0] px_g"
    assert_includes wrapper, "input  [   7:0] px_b"
    assert_includes wrapper, "output [   7:0] px_out_r"
    assert_includes wrapper, "output [   7:0] px_out_g"
    assert_includes wrapper, "output [   7:0] px_out_b"
    # Direct port connections (no intermediate SV wire)
    assert_includes wrapper, ".px_r(px_r)"
    assert_includes wrapper, ".px_out_r(px_out_r)"
  end

  def test_v_wrapper_mem_bundle_port
    klass = module_class("WrapMemBundle") do
      fifo_in = iodecl("fifo", WrapTestPixel.new)
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

  private

  def module_class(name, &build_block)
    build_block ||= proc {}

    Class.new(RSV::ModuleDef) do
      define_singleton_method(:name) { name }
      define_method(:build, &build_block)
    end
  end
end
