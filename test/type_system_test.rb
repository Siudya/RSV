# frozen_string_literal: true

require "minitest/autorun"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "rsv"

# ── 类型系统测试 ─────────────────────────────────────────────────────────────
# 覆盖: bit/bits/uint/sint/clock/reset 类型构造, 匿名类型,
#       DataType 运行时算术, as_sint, inout 端口

class TypeSystemTest < Minitest::Test
  # ── bits & uint 等价 ────────────────────────────────────────────────────

  def test_bits_is_equivalent_to_uint
    mod = module_class("BitsAlias") do
      input("a", bits(8))
      output("b", uint(8))
    end.new

    sv = mod.to_sv
    assert_includes sv, "logic [7:0] a"
    assert_includes sv, "logic [7:0] b"
  end

  # ── sint ────────────────────────────────────────────────────────────────

  def test_sint_emits_signed_logic
    mod = module_class("SintDecl") do
      input("a", sint(16))
      output("b", sint(8))
      w = wire("w", sint(32))
      r = reg("r", sint(16))
    end.new

    sv = mod.to_sv
    assert_includes sv, "logic signed [15:0] a"
    assert_includes sv, "logic signed [7:0]  b"
    assert_includes sv, "logic signed [31:0] w"
    assert_includes sv, "logic signed [15:0] r"
  end

  # ── as_sint ─────────────────────────────────────────────────────────────

  def test_as_sint_emits_dollar_signed
    mod = module_class("AsSintTop") do
      a = input("a", uint(8))
      b = output("b", sint(8))
      b <= a.as_sint
    end.new

    sv = mod.to_sv
    assert_includes sv, "assign b = $signed(a);"
  end

  # ── clock 类型 ──────────────────────────────────────────────────────────

  def test_clock_neg_emits_negedge
    mod = module_class("ClkNeg") do
      clk = input("clk", clock)
      rst = input("rst", reset)
      cnt = reg("cnt", uint(8), init: 0)

      with_clk_and_rst(clk.neg, rst)
      always_ff do
        svif(1) do
          cnt <= cnt + 1
        end
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "always_ff @(negedge clk or posedge rst)"
  end

  # ── reset 类型 ──────────────────────────────────────────────────────────

  def test_reset_neg_emits_negedge_and_inverted_condition
    mod = module_class("RstNeg") do
      clk = input("clk", clock)
      rst = input("rst", reset)
      cnt = reg("cnt", uint(8), init: 0)

      with_clk_and_rst(clk, rst.neg)
      always_ff do
        svif(1) do
          cnt <= cnt + 1
        end
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "always_ff @(posedge clk or negedge rst)"
    assert_includes sv, "if (!rst)"
  end

  def test_clock_and_reset_both_negated
    mod = module_class("BothNeg") do
      clk = input("clk", clock)
      rst = input("rst_n", reset)
      cnt = reg("cnt", uint(8), init: 0)

      with_clk_and_rst(clk.neg, rst.neg)
      always_ff do
        svif(1) do
          cnt <= cnt + 1
        end
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "always_ff @(negedge clk or negedge rst_n)"
    assert_includes sv, "if (!rst_n)"
  end

  def test_clock_reset_positive_edge_default
    mod = module_class("PosEdge") do
      clk = input("clk", clock)
      rst = input("rst", reset)
      cnt = reg("cnt", uint(8), init: 0)

      with_clk_and_rst(clk, rst)
      always_ff do
        svif(1) do
          cnt <= cnt + 1
        end
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "always_ff @(posedge clk or posedge rst)"
    assert_includes sv, "if (rst)"
  end

  # ── inout 端口 ──────────────────────────────────────────────────────────

  def test_inout_port_emits_inout_logic
    mod = module_class("InoutPort") do
      inout("sda", bit)
      inout("bus", uint(8))
    end.new

    sv = mod.to_sv
    assert_includes sv, "inout logic"
    assert_includes sv, "sda"
    assert_includes sv, "bus"
  end

  # ── 匿名数据类型 ───────────────────────────────────────────────────────

  def test_named_hardware_uses_anonymous_data_types
    mod = module_class("AnonTypes") do
      bit_t = bit
      word_t = uint(16)
      mem_p = vec(8, word_t)
      mem_t = vec(16, word_t)

      input("clk", bit_t)
      input("rst", bit_t)
      out = output("out", word_t)

      wire("wire_a", bit_t)
      wire_b = wire("wire_b", word_t)
      reg("reg_c", mem_p)
      reg("reg_d", mem_t)

      out <= wire_b
    end.new

    expected = <<~SV.chomp
      module AnonTypes (
        input  logic        clk,
        input  logic        rst,
        output logic [15:0] out
      );

        logic        wire_a;
        logic [15:0] wire_b;
        logic [15:0] reg_c[7:0];
        logic [15:0] reg_d[15:0];

        assign out = wire_b;

      endmodule
    SV

    assert_equal expected, mod.to_sv
  end

  def test_fill_helpers_drive_reset_for_unpacked_regs
    mod = module_class("InitShapes") do
      bit_t = bit
      word_t = uint(16)
      mem_p = vec(8, word_t)
      mem_t = vec(16, word_t)

      clk = input("clk", bit_t)
      rst = input("rst", bit_t)
      reg_p = reg("reg_p", mem_p, init: vec.fill(8, uint(16, 0x75)))
      reg_m = reg("reg_m", mem_t, init: vec.fill(16, uint(16, 0x33)))

      with_clk_and_rst(clk, rst)
      always_ff do
        reg_p[0] <= 0
        reg_m[0] <= reg_p[0]
      end
    end.new

    expected = <<~SV.chomp
      module InitShapes (
        input logic clk,
        input logic rst
      );

        logic [15:0] reg_p[7:0];
        logic [15:0] reg_m[15:0];

        always_ff @(posedge clk or posedge rst) begin
          if (rst) begin
            for (int reg_p_idx_0 = 0; reg_p_idx_0 < 8; reg_p_idx_0 = reg_p_idx_0 + 1) begin
              reg_p[reg_p_idx_0] <= 16'h75;
            end
            for (int reg_m_idx_0 = 0; reg_m_idx_0 < 16; reg_m_idx_0 = reg_m_idx_0 + 1) begin
              reg_m[reg_m_idx_0] <= 16'h33;
            end
          end else begin
            reg_p[0] <= 16'd0;
            reg_m[0] <= reg_p[0];
          end
        end

      endmodule
    SV

    assert_equal expected, mod.to_sv
  end

  def test_wire_descriptor_mode_returns_wire_type
    desc = nil
    mod = module_class("WireDescTest") do
      desc = wire(uint(8))
    end.new
    assert_kind_of RSV::WireType, desc
    assert_empty mod.locals
  end

  # ── 运行时 DataType 算术 ───────────────────────────────────────────────

  def test_runtime_uint_arithmetic
    a = RSV::DataType.new(width: 8, init: 10)
    b = RSV::DataType.new(width: 8, init: 5)

    sum = a + b
    assert_equal 15, sum.init
    assert_equal 9, sum.width

    product = a * b
    assert_equal 50, product.init
    assert_equal 16, product.width

    diff = a - b
    assert_equal 5, diff.init

    quotient = a / b
    assert_equal 2, quotient.init
  end

  def test_runtime_sint_arithmetic
    a = RSV::DataType.new(width: 8, signed: true, init: 10)
    b = RSV::DataType.new(width: 8, signed: true, init: 3)

    sum = a + b
    assert_equal 13, sum.init
    assert sum.signed
  end

  def test_runtime_reduce_operations
    val = RSV::DataType.new(width: 4, init: 0b1010)
    assert_equal 1, val.or_r.init
    assert_equal 0, val.and_r.init

    full = RSV::DataType.new(width: 4, init: 0b1111)
    assert_equal 1, full.and_r.init
  end

  def test_runtime_compare
    a = RSV::DataType.new(width: 8, init: 10)
    b = RSV::DataType.new(width: 8, init: 10)
    c = RSV::DataType.new(width: 8, init: 5)

    assert_equal 1, a.eq(b).init
    assert_equal 0, a.eq(c).init
    assert_equal 0, a.ne(b).init
    assert_equal 1, a.ne(c).init
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
