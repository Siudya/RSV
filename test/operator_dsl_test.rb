# frozen_string_literal: true

require "minitest/autorun"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "rsv"

class OperatorDslTest < Minitest::Test
  def test_expanded_operators_emit_systemverilog_forms
    mod = module_class("OperatorTop") do
      a = input("a", uint(8))
      b = input("b", uint(8))
      out = output("out", uint(8))

      eq = wire("eq", bit)
      neq = wire("neq", bit)
      logic_and = wire("logic_and", bit)
      logic_or = wire("logic_or", bit)
      red_or = wire("red_or", bit)
      red_and = wire("red_and", bit)
      inv = wire("inv", bit)
      bit_inv = wire("bit_inv", uint(8))
      shl = wire("shl", uint(8))
      shr = wire("shr", uint(8))
      mul = wire("mul", uint(8))
      div = wire("div", uint(8))
      mod_val = wire("mod_val", uint(8))
      slice_a = wire("slice_a", uint(4))
      slice_b = wire("slice_b", uint(4))
      slice_up = wire("slice_up", uint(4))
      slice_down = wire("slice_down", uint(4))
      tmp = wire("tmp", uint(8))

      eq <= a.eq(b)
      neq <= a.ne(b)
      logic_and <= a.and(b)
      logic_or <= a.or(b)
      red_or <= a.or_r
      red_and <= b.and_r
      inv <= !eq
      bit_inv <= ~a
      shl <= (a << 1)
      shr <= (b >> 1)
      mul <= (a * b)
      div <= (a / 3)
      mod_val <= (a % 3)
      slice_a <= a[7, 4]
      slice_b <= b[7..4]
      slice_up <= a[2, :+, 4]
      slice_down <= b[5, :-, 4]

      always_comb do
        svif(a.le(b)) do
          tmp <= a
        end
        svelse do
          tmp <= b
        end
      end

      tmp >= out
    end.new

    expected = <<~SV.chomp
      module OperatorTop (
        input  logic [7:0] a,
        input  logic [7:0] b,
        output logic [7:0] out
      );

        logic       eq;
        logic       neq;
        logic       logic_and;
        logic       logic_or;
        logic       red_or;
        logic       red_and;
        logic       inv;
        logic [7:0] bit_inv;
        logic [7:0] shl;
        logic [7:0] shr;
        logic [7:0] mul;
        logic [7:0] div;
        logic [7:0] mod_val;
        logic [3:0] slice_a;
        logic [3:0] slice_b;
        logic [3:0] slice_up;
        logic [3:0] slice_down;
        logic [7:0] tmp;

        assign eq         = a == b;
        assign neq        = a != b;
        assign logic_and  = a && b;
        assign logic_or   = a || b;
        assign red_or     = |a;
        assign red_and    = &b;
        assign inv        = !eq;
        assign bit_inv    = ~a;
        assign shl        = a << 8'd1;
        assign shr        = b >> 8'd1;
        assign mul        = a * b;
        assign div        = a / 8'd3;
        assign mod_val    = a % 8'd3;
        assign slice_a    = a[7:4];
        assign slice_b    = b[7:4];
        assign slice_up   = a[2 +: 4];
        assign slice_down = b[5 -: 4];

        always_comb begin
          if (a <= b) begin
            tmp = a;
          end else begin
            tmp = b;
          end
        end

        assign out = tmp;

      endmodule
    SV

    assert_equal expected, mod.to_sv
  end

  def test_left_and_right_assignment_forms_are_equivalent
    mod = module_class("AssignDir") do
      a = input("a", uint(8))
      left = output("left", uint(8))
      right = output("right", uint(8))

      left <= a
      a >= right
    end.new

    sv = mod.to_sv

    assert_includes sv, "assign left  = a;"
    assert_includes sv, "assign right = a;"
  end

  def test_old_operator_aliases_are_removed
    sig = RSV::SignalHandler.new("sig", width: 8, kind: :wire)

    assert_respond_to sig, :eq
    assert_respond_to sig, :ne
    assert_respond_to sig, :lt
    assert_respond_to sig, :le
    assert_respond_to sig, :gt
    assert_respond_to sig, :ge
    assert_respond_to sig, :and
    assert_respond_to sig, :or
    assert_respond_to sig, :and_r
    assert_respond_to sig, :or_r

    refute_respond_to sig, :neq
    refute_respond_to sig, :leq
    refute_respond_to sig, :geq
    refute_respond_to sig, :and_
    refute_respond_to sig, :or_
    refute_respond_to sig, :reduce_and
    refute_respond_to sig, :reduce_or
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
