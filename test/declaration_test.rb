# frozen_string_literal: true

require "minitest/autorun"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "rsv"

# ── 声明测试 ─────────────────────────────────────────────────────────────────
# 覆盖: 端口声明, wire/reg/const, expr, attr 属性, 对齐, meta_param

class MetaParamDeclTestModule < RSV::ModuleDef
  def build(width: 8)
    input("d", uint(width))
    output("q", uint(width))
  end
end

class MetaParamDeclExprModule < RSV::ModuleDef
  def build(n: 4)
    a = input("a", uint(n))
    y = output("y", uint(n))
    y <= a + n
  end
end

class DeclarationTest < Minitest::Test
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

  # ── Meta parameter tests ─────────────────────────────────────────────

  def test_meta_param_declares_no_parameter
    mod = MetaParamDeclTestModule.new("meta_param_test", width: 8)
    sv = mod.to_sv
    refute_includes sv, "parameter"
    assert_includes sv, "[7:0]"
  end

  def test_meta_param_override
    mod = MetaParamDeclTestModule.new("meta_param_override", width: 32)
    sv = mod.to_sv
    assert_includes sv, "[31:0]"
    refute_includes sv, "parameter"
  end

  def test_meta_param_in_expression
    mod = MetaParamDeclExprModule.new("meta_param_expr", n: 4)
    sv = mod.to_sv
    assert_includes sv, "assign y = a + 4'd4;"
  end

  def test_meta_params_different_widths
    unsigned_mod = MetaParamDeclTestModule.new("meta_u", width: 8)
    sv = unsigned_mod.to_sv
    assert_includes sv, "[7:0]"

    wide_mod = MetaParamDeclTestModule.new("meta_w", width: 16)
    sv = wide_mod.to_sv
    assert_includes sv, "[15:0]"
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
