# frozen_string_literal: true

require "minitest/autorun"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "rsv"

class AnonymousTypeDslTest < Minitest::Test
  def test_named_hardware_uses_anonymous_data_types
    mod = module_class("AnonTypes") do
      bit_t = bit
      word_t = uint(16)
      packed_t = arr(8, word_t)
      mem_t = mem(16, word_t)

      input("clk", bit_t)
      input("rst", bit_t)
      out = output("out", word_t)

      wire("wire_a", bit_t)
      wire_b = wire("wire_b", word_t)
      reg("reg_c", packed_t)
      reg("reg_d", mem_t)

      out <= wire_b
    end.new

    expected = <<~SV.chomp
      module AnonTypes (
        input  logic        clk,
        input  logic        rst,
        output logic [15:0] out
      );

        logic             wire_a;
        logic [15:0]      wire_b;
        logic [7:0][15:0] reg_c;
        logic [15:0]      reg_d[15:0];

        assign out = wire_b;

      endmodule
    SV

    assert_equal expected, mod.to_sv
  end

  def test_fill_helpers_drive_reset_for_packed_and_unpacked_regs
    mod = module_class("InitShapes") do
      bit_t = bit
      word_t = uint(16)
      packed_t = arr(8, word_t)
      mem_t = mem(16, word_t)

      clk = input("clk", bit_t)
      rst = input("rst", bit_t)
      reg_p = reg("reg_p", packed_t, init: arr.fill(8, uint(16, 0x75)))
      reg_m = reg("reg_m", mem_t, init: mem.fill(16, uint(16, 0x33)))

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

        logic [7:0][15:0] reg_p;
        logic [15:0]      reg_m[15:0];

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

  def test_legacy_named_type_api_is_removed
    assert_raises(ArgumentError, TypeError) do
      module_class("LegacyDecl") do
        wire(uint("legacy", 8))
      end.new
    end
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
