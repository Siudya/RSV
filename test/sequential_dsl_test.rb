# frozen_string_literal: true

require "minitest/autorun"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "rsv"

class SequentialDslTest < Minitest::Test
  def test_expr_creates_inferred_wire_and_assign
    c = nil
    mod = RSV::ModuleDef.new("ExprTop") do
      a = wire(uint("a", width: 4))
      b = logic(uint("b", width: 16))
      c = expr("c", a + b)

      assign_stmt(b, c)
    end

    expected = <<~SV.chomp
      module ExprTop (
      );

        wire  [3:0]  a;
        logic [15:0] b;
        wire  [15:0] c;

        assign c = a + b;
        assign b = c;

      endmodule
    SV

    assert_equal "c", c.name
    assert_equal 16, c.width
    assert_equal expected, mod.to_sv
  end

  def test_reg_assignment_requires_always_ff_or_always_latch
    error = assert_raises(ArgumentError) do
      RSV::ModuleDef.new("BadRegAssign") do
        a = wire(uint("a", width: 8))
        r = reg(uint("r", width: 8, init: 0))

        assign_stmt(r, a)
      end.to_sv
    end

    assert_equal "reg signal r must be assigned inside always_ff or always_latch", error.message
  end

  def test_logic_can_be_assigned_in_assign_and_always_comb
    mod = RSV::ModuleDef.new("LogicAssigns") do
      a = input(uint("a", width: 8))
      out = output(uint("out", width: 8))
      tmp = logic(uint("tmp", width: 8))

      assign_stmt(out, tmp)

      always_comb do
        assign(tmp, a)
      end
    end

    expected = <<~SV.chomp
      module LogicAssigns (
        input  logic [7:0] a,
        output logic [7:0] out
      );

        logic [7:0] tmp;

        assign out = tmp;

        always_comb begin
          tmp = a;
        end

      endmodule
    SV

    assert_equal expected, mod.to_sv
  end

  def test_reg_cannot_be_assigned_in_always_comb
    error = assert_raises(ArgumentError) do
      RSV::ModuleDef.new("BadRegComb") do
        a = input(uint("a", width: 8))
        r = reg(uint("r", width: 8, init: 0))

        always_comb do
          assign(r, a)
        end
      end.to_sv
    end

    assert_equal "reg signal r must be assigned inside always_ff or always_latch", error.message
  end

  def test_expr_inlines_anonymous_intermediate_expressions
    d = nil
    mod = RSV::ModuleDef.new("InlineExpr") do
      a = wire(uint("a", width: 8))
      b = wire(uint("b", width: 8))
      c = a + b
      d = expr("d", c + a)
    end

    expected = <<~SV.chomp
      module InlineExpr (
      );

        wire [7:0] a;
        wire [7:0] b;
        wire [7:0] d;

        assign d = (a + b) + a;

      endmodule
    SV

    assert_equal "d", d.name
    assert_equal 8, d.width
    assert_equal expected, mod.to_sv
  end

  def test_reg_can_be_assigned_in_always_latch
    mod = RSV::ModuleDef.new("LatchTop") do
      en = input(uint("en"))
      d = input(uint("d", width: 8))
      q = reg(uint("q", width: 8))

      always_latch do
        when_(en) do
          q <= d
        end
      end
    end

    expected = <<~SV.chomp
      module LatchTop (
        input logic       en,
        input logic [7:0] d
      );

        logic [7:0] q;

        always_latch begin
          if (en) begin
            q <= d;
          end
        end

      endmodule
    SV

    assert_equal expected, mod.to_sv
  end

  def test_reg_declarations_emit_resettable_always_ff
    mod = RSV::ModuleDef.new("Counter") do
      clk0 = input(uint("clk_0"))
      rst0 = input(uint("rst_0"))
      cnt = reg(uint("cnt", width: 16, init: 0x75))
      err = logic(uint("err", width: 16))

      with_clk_and_rst(clk0, rst0)
      always_ff do
        when_(cnt < 85) do
          cnt <= cnt + 1
          err[0] <= (cnt > 85)
        end
      end
    end

    expected = <<~SV.chomp
      module Counter (
        input logic clk_0,
        input logic rst_0
      );

        logic [15:0] cnt;
        logic [15:0] err;

        always_ff @(posedge clk_0 or posedge rst_0) begin
          if (rst_0) begin
            cnt <= 16'h75;
          end else if (cnt < 16'd85) begin
            cnt <= cnt + 16'd1;
            err[0] <= cnt > 16'd85;
          end
        end

      endmodule
    SV

    assert_equal expected, mod.to_sv
  end

  def test_with_clk_and_rst_switches_sequential_domain
    mod = RSV::ModuleDef.new("Top") do
      clk0 = input(uint("clk_0"))
      rst0 = input(uint("rst_0"))
      clk1 = input(uint("clk_1"))
      rst1 = input(uint("rst_1"))
      cnt0 = reg(uint("cnt0", width: 16, init: 0x75))
      cnt1 = reg(uint("cnt1", width: 16, init: 0x45))

      with_clk_and_rst(clk0, rst0)
      always_ff do
        when_(cnt0 < 85) do
          cnt0 <= cnt0 + 1
        end
      end

      with_clk_and_rst(clk1, rst1)
      always_ff do
        when_(cnt1 < 97) do
          cnt1 <= cnt1 + 1
        end
      end
    end

    sv = mod.to_sv

    assert_includes sv, "always_ff @(posedge clk_0 or posedge rst_0) begin"
    assert_includes sv, "cnt0 <= 16'h75;"
    assert_includes sv, "always_ff @(posedge clk_1 or posedge rst_1) begin"
    assert_includes sv, "cnt1 <= 16'h45;"
    assert_includes sv, "cnt1 < 16'd97"
  end
end
