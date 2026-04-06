# frozen_string_literal: true

require "minitest/autorun"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "rsv"

# ── 声明测试 ─────────────────────────────────────────────────────────────────
# 覆盖: 端口声明, wire/reg/const, expr, attr 属性, 对齐, meta_param

class MetaParamDeclTestModule < RSV::ModuleDef
  def build(width: 8)
    iodecl("d", input(uint(width)))
    iodecl("q", output(uint(width)))
  end
end

class MetaParamDeclExprModule < RSV::ModuleDef
  def build(n: 4)
    a = iodecl("a", input(uint(n)))
    y = iodecl("y", output(uint(n)))
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
    assert_respond_to mod, :vec
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
      clk = iodecl("clk", input(clock))
      rst_n = iodecl("rst_n", input(reset))
      count = iodecl("count", output(uint(16)))
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
      out = iodecl("out", output(sint(16)))
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
      iodecl("clk", input(bit), attr: { "mark_debug" => "\"true\"" })
      iodecl("dout", output(uint(8)), attr: { "keep" => nil })
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
      a = iodecl("a", input(uint(8)))
      short = wire("x", uint(8))
      long_name = wire("long_name", uint(8))
      y = iodecl("y", output(uint(8)))

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

  # ── let form shorthand tests ──────────────────────────────────────

  def test_let_form_declares_ports_and_locals
    mod = module_class("LetForm") {
      let :clk, input(clock)
      let :rst, input(reset)
      let :en, input(bit)
      let :count, output(uint(8))
      reg :count_r, uint(8), init: 0
      expr :count_next, count_r + 1
      count_r >= count
      with_clk_and_rst(clk, rst)
      always_ff { svif(en) { count_r <= count_next } }
    }.new

    sv = mod.to_sv
    assert_includes sv, "input  logic       clk"
    assert_includes sv, "output logic [7:0] count"
    assert_includes sv, "logic [7:0] count_r"
    assert_includes sv, "assign count_next = count_r + 8'd1"
    assert_includes sv, "count_r <= count_next"
  end

  def test_let_form_wire_and_const
    mod = module_class("LetWireConst") {
      let :a, input(uint(8))
      let :y, output(uint(8))
      wire :tmp, uint(8)
      # SV const 一般大写，Ruby 大写标识符是常量，需用 String 形式
      offset = const("OFFSET", uint(8, 42))
      tmp <= a + offset
      y <= tmp
    }.new

    sv = mod.to_sv
    assert_includes sv, "tmp"
    assert_includes sv, "localparam"
    assert_includes sv, "OFFSET = 8'h2a"
    assert_includes sv, "assign tmp = a + OFFSET"
  end

  def test_let_form_accessible_in_always_blocks
    mod = module_class("LetAlways") {
      let :clk, input(clock)
      let :rst, input(reset)
      let :d, input(uint(4))
      let :q, output(uint(4))
      reg :r, uint(4), init: 0
      q <= r
      with_clk_and_rst(clk, rst)
      always_ff { r <= d }
    }.new

    sv = mod.to_sv
    assert_includes sv, "r <= d"
    assert_includes sv, "assign q = r"
  end

  # ── let form tests ───────────────────────────────────────────────────

  def test_let_form_ports
    mod = module_class("LetPorts") {
      let :clk, input(clock)
      let :rst, input(reset)
      let :din, input(uint(8))
      let :dout, output(uint(8))
      dout <= din
    }.new

    sv = mod.to_sv
    assert_includes sv, "input  logic       clk"
    assert_includes sv, "input  logic       rst"
    assert_includes sv, "input  logic [7:0] din"
    assert_includes sv, "output logic [7:0] dout"
    assert_includes sv, "assign dout = din"
  end

  def test_let_form_wire_and_reg
    mod = module_class("LetWireReg") {
      let :clk, input(clock)
      let :rst, input(reset)
      let :d,   input(uint(4))
      let :q,   output(uint(4))
      let :tmp, wire(uint(4))
      let :r,   reg(uint(4), init: 0)
      tmp <= d
      q <= r
      with_clk_and_rst(clk, rst)
      always_ff { r <= tmp }
    }.new

    sv = mod.to_sv
    assert_includes sv, "logic [3:0] tmp"
    assert_includes sv, "logic [3:0] r"
    assert_includes sv, "r <= tmp"
    assert_includes sv, "= 4'h0"
  end

  def test_let_form_reg_with_init_on_type
    mod = module_class("LetRegInitOnType") {
      let :clk, input(clock)
      let :rst, input(reset)
      let :cnt, reg(uint(width: 16, init: 0x15))
      with_clk_and_rst(clk, rst)
      always_ff { cnt <= cnt + 1 }
    }.new

    sv = mod.to_sv
    assert_includes sv, "logic [15:0] cnt"
    assert_includes sv, "= 16'h15"
  end

  def test_let_form_const_and_expr
    mod = module_class("LetConstExpr") {
      let :a,    input(uint(8))
      let :y,    output(uint(8))
      let :base, const(uint(8, 0x10))
      let :sum,  expr(a + base)
      y <= sum
    }.new

    sv = mod.to_sv
    assert_includes sv, "localparam"
    assert_includes sv, "base = 8'h10"
    assert_includes sv, "assign sum = a + base"
    assert_match(/assign y\s+= sum/, sv)
  end

  def test_let_form_accessible_in_always_blocks
    mod = module_class("LetAlways") {
      let :clk,    input(clock)
      let :rst,    input(reset)
      let :enable, input(bit)
      let :cnt,    reg(uint(8), init: 0)
      let :out,    output(uint(8))
      out <= cnt
      with_clk_and_rst(clk, rst)
      always_ff { svif(enable) { cnt <= cnt + 1 } }
    }.new

    sv = mod.to_sv
    assert_includes sv, "cnt <= cnt + 8'd1"
    assert_includes sv, "assign out = cnt"
  end

  def test_let_form_mixed_with_string_forms
    mod = module_class("LetMixed") {
      let :a, input(uint(8))
      let :b, input(uint(8))
      c = iodecl("c", input(uint(8)))
      let :y, output(uint(8))
      y <= a + b + c
    }.new

    sv = mod.to_sv
    assert_includes sv, "input  logic [7:0] a"
    assert_includes sv, "input  logic [7:0] b"
    assert_includes sv, "input  logic [7:0] c"
    assert_includes sv, "assign y = a + b + c"
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
