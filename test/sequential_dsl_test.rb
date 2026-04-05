# frozen_string_literal: true

require "minitest/autorun"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "rsv"

class SequentialDslTest < Minitest::Test
  def test_expr_creates_inferred_logic_and_assign
    c = nil
    mod = module_class("ExprTop") do
      a = wire("a", uint(4))
      b = wire("b", uint(16))
      out = output("out", uint(16))
      c = expr("c", a + b)

      out <= c
    end.new

    expected = <<~SV.chomp
      module ExprTop (
        output logic [15:0] out
      );

        logic [3:0]  a;
        logic [15:0] b;
        logic [15:0] c;

        assign c   = a + b;
        assign out = c;

      endmodule
    SV

    assert_equal "c", c.name
    assert_equal 16, c.width
    assert_equal expected, mod.to_sv
  end

  def test_reg_assignment_requires_always_ff_or_always_latch
      error = assert_raises(ArgumentError) do
        module_class("BadRegAssign") do
        a = wire("a", uint(8))
        r = reg("r", uint(8), init: 0)

        r <= a
        end.new.to_sv
    end

    assert_equal "reg signal r must be assigned inside always_ff or always_latch", error.message
  end

  def test_wire_can_be_assigned_in_assign_and_always_comb
    mod = module_class("WireAssigns") do
      a = input("a", uint(8))
      out = output("out", uint(8))
      tmp = wire("tmp", uint(8))

      out <= tmp

      always_comb do
        tmp <= a
      end
    end.new

    expected = <<~SV.chomp
      module WireAssigns (
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
        module_class("BadRegComb") do
        a = input("a", uint(8))
        r = reg("r", uint(8), init: 0)

        always_comb do
          r <= a
        end
      end.new.to_sv
    end

    assert_equal "reg signal r must be assigned inside always_ff or always_latch", error.message
  end

  def test_wire_cannot_be_assigned_in_always_ff
      error = assert_raises(ArgumentError) do
        module_class("BadWireFf") do
        clk = input("clk", bit)
        rst = input("rst", bit)
        d = input("d", uint(8))
        w = wire("w", uint(8))

        with_clk_and_rst(clk, rst)
        always_ff do
          svif(1) do
            w <= d
          end
        end
      end.new.to_sv
    end

    assert_equal "wire signal w must be assigned inside always_comb or outside procedural blocks", error.message
  end

  def test_wire_cannot_be_assigned_in_always_latch
      error = assert_raises(ArgumentError) do
        module_class("BadWireLatch") do
        en = input("en", bit)
        d = input("d", uint(8))
        w = wire("w", uint(8))

        always_latch do
          svif(en) do
            w <= d
          end
        end
      end.new.to_sv
    end

    assert_equal "wire signal w must be assigned inside always_comb or outside procedural blocks", error.message
  end

  def test_signal_cannot_be_assigned_by_assign_and_always_block
      error = assert_raises(ArgumentError) do
        module_class("MixedDrivers") do
        a = input("a", uint(8))
        b = input("b", uint(8))
        w = wire("w", uint(8))

        w <= a

        always_comb do
          w <= b
        end
      end.new.to_sv
    end

    assert_equal "signal w cannot be assigned in multiple always/assign blocks", error.message
  end

  def test_signal_cannot_be_assigned_in_multiple_always_blocks
      error = assert_raises(ArgumentError) do
        module_class("DoubleAlways") do
        a = input("a", uint(8))
        b = input("b", uint(8))
        w = wire("w", uint(8))

        always_comb do
          w <= a
        end

        always_comb do
          w <= b
        end
      end.new.to_sv
    end

    assert_equal "signal w cannot be assigned in multiple always/assign blocks", error.message
  end

  def test_explicit_logic_declaration_is_removed
    assert_raises(NoMethodError) do
      module_class("NoLogic") do
        logic("tmp", uint(8))
      end.new
    end
  end

  def test_expr_inlines_anonymous_intermediate_expressions
    d = nil
    mod = module_class("InlineExpr") do
      a = wire("a", uint(8))
      b = wire("b", uint(8))
      c = a + b
      d = expr("d", c + a)
    end.new

    expected = <<~SV.chomp
      module InlineExpr (
      );

        logic [7:0] a;
        logic [7:0] b;
        logic [7:0] d;

        assign d = a + b + a;

      endmodule
    SV

    assert_equal "d", d.name
    assert_equal 8, d.width
    assert_equal expected, mod.to_sv
  end

  def test_reg_can_be_assigned_in_always_latch_using_blocking_assignment
    mod = module_class("LatchTop") do
      en = input("en", bit)
      d = input("d", uint(8))
      q = reg("q", uint(8))

      always_latch do
        svif(en) do
          q <= d
        end
      end
    end.new

    expected = <<~SV.chomp
      module LatchTop (
        input logic       en,
        input logic [7:0] d
      );

        logic [7:0] q;

        always_latch begin
          if (en) begin
            q = d;
          end
        end

      endmodule
    SV

    assert_equal expected, mod.to_sv
  end

  def test_reg_declarations_emit_resettable_always_ff
    mod = module_class("Counter") do
      clk0 = input("clk_0", bit)
      rst0 = input("rst_0", bit)
      cnt = reg("cnt", uint(16), init: 0x75)
      err = reg("err", uint(16))

      with_clk_and_rst(clk0, rst0)
      always_ff do
        svif(cnt.lt(85)) do
          cnt <= cnt + 1
          err[0] <= cnt.gt(85)
        end
      end
    end.new

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
    mod = module_class("Top") do
      clk0 = input("clk_0", bit)
      rst0 = input("rst_0", bit)
      clk1 = input("clk_1", bit)
      rst1 = input("rst_1", bit)
      cnt0 = reg("cnt0", uint(16), init: 0x75)
      cnt1 = reg("cnt1", uint(16), init: 0x45)

      with_clk_and_rst(clk0, rst0)
      always_ff do
        svif(cnt0.lt(85)) do
          cnt0 <= cnt0 + 1
        end
      end

      with_clk_and_rst(clk1, rst1)
      always_ff do
        svif(cnt1.lt(97)) do
          cnt1 <= cnt1 + 1
        end
      end
    end.new

    sv = mod.to_sv

    assert_includes sv, "always_ff @(posedge clk_0 or posedge rst_0) begin"
    assert_includes sv, "cnt0 <= 16'h75;"
    assert_includes sv, "always_ff @(posedge clk_1 or posedge rst_1) begin"
    assert_includes sv, "cnt1 <= 16'h45;"
    assert_includes sv, "cnt1 < 16'd97"
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
