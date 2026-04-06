# frozen_string_literal: true

require "minitest/autorun"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "rsv"

# ── 流式API测试 ──────────────────────────────────────────────────────────────
# 覆盖: sv_take, sv_select, sv_foreach, sv_reduce, sv_map (uint/mem/bit)

class StreamTest < Minitest::Test
  def test_uint_stream_foreach_reduce_and_map_emit_expected_sv
    mod = module_class("UintStream") do
      clk = input("clk", clock)
      rst = input("rst", reset)
      old_mask = reg("om", uint(16))
      new_mask = reg("nm", uint(16, 0))
      update = input("m_upd", bit)
      parity = output("e_par", bit)
      result = output("res", uint(4))

      with_clk_and_rst(clk, rst)
      always_ff do
        svif(update) do
          new_mask
            .sv_take(8)
            .sv_select { |_, i| i.even? }
            .sv_foreach { |v, i| v <= old_mask[i] }
        end
      end

      always_comb do
        parity <= new_mask.sv_take(4).sv_reduce { |a, b| a ^ b }
        result <= new_mask
          .sv_take(8)
          .sv_select { |_, i| i.even? }
          .sv_map { |v, _i| v }
      end
    end.new

    sv = mod.to_sv

    assert_includes sv, "if (rst) begin"
    assert_includes sv, "nm <= 16'h0;"
    assert_includes sv, "nm[0] <= om[0];"
    assert_includes sv, "nm[2] <= om[2];"
    assert_includes sv, "nm[4] <= om[4];"
    assert_includes sv, "nm[6] <= om[6];"
    assert_includes sv, "e_par = ((nm[0] ^ nm[1]) ^ nm[2]) ^ nm[3];"
    assert_includes sv, "res = {nm[6], nm[4], nm[2], nm[0]};"
  end

  def test_mem_stream_map_preserves_word_order
    mod = module_class("MemArrStream") do
      words = input("words", mem([4], uint(8)))
      out = output("out", mem([2], uint(8)))

      out <= words
        .sv_take(4)
        .sv_select { |_, i| i < 2 }
        .sv_map { |v, _i| v }
    end.new

    sv = mod.to_sv

    assert_includes sv, "output logic [7:0] out[1:0]"
    assert_includes sv, "assign out = {words[1], words[0]};"
  end

  def test_mem_bit_stream_foreach_reduce_and_map_emit_expected_sv
    mod = module_class("MemBitStream") do
      clk = input("clk", clock)
      rst = input("rst", reset)
      src = input("src", mem([8], bit))
      dst = reg("dst", mem([8], bit), init: mem.fill(8, bit(0)))
      update = input("m_upd", bit)
      parity = output("e_par", bit)
      result = output("res", uint(4))

      with_clk_and_rst(clk, rst)
      always_ff do
        svif(update) do
          src
            .sv_take(8)
            .sv_select { |_, i| i.even? }
            .sv_foreach { |v, i| dst[i] <= v }
        end
      end

      always_comb do
        parity <= src.sv_take(4).sv_reduce { |a, b| a ^ b }
        result <= src
          .sv_take(8)
          .sv_select { |_, i| i.even? }
          .sv_map { |v, _i| v }
      end
    end.new

    sv = mod.to_sv

    assert_includes sv, "dst[0] <= src[0];"
    assert_includes sv, "dst[2] <= src[2];"
    assert_includes sv, "dst[4] <= src[4];"
    assert_includes sv, "dst[6] <= src[6];"
    assert_includes sv, "e_par = ((src[0] ^ src[1]) ^ src[2]) ^ src[3];"
    assert_includes sv, "res = {src[6], src[4], src[2], src[0]};"
  end

  def test_mem_word_stream_map_preserves_word_order
    mod = module_class("MemWordStream") do
      words = input("words", mem([4], uint(8)))
      out = output("out", mem([2], uint(8)))
      out <= words
        .sv_take(4)
        .sv_select { |_, i| i < 2 }
        .sv_map { |v, _i| v }
    end.new

    sv = mod.to_sv

    assert_includes sv, "input  logic [7:0] words[3:0]"
    assert_includes sv, "assign out = {words[1], words[0]};"
  end

  def test_mixed_multidim_stream_foreach_supports_nested_views
    mod = module_class("MixedStreamForeach") do
      clk = input("clk", clock)
      rst = input("rst", reset)
      data = input("data", mem([2], mem([3], uint(8))))
      out = reg("out", mem([2], mem([3], uint(8))), init: mem.fill(2, mem.fill(3, uint(8, 0))))

      with_clk_and_rst(clk, rst)
      always_ff do
        data.sv_take(2).sv_foreach do |row, i|
          row
            .sv_take(3)
            .sv_select { |_, j| j.even? }
            .sv_foreach { |v, j| out[i][j] <= v }
        end
      end
    end.new

    sv = mod.to_sv

    assert_includes sv, "out[0][0] <= data[0][0];"
    assert_includes sv, "out[0][2] <= data[0][2];"
    assert_includes sv, "out[1][0] <= data[1][0];"
    assert_includes sv, "out[1][2] <= data[1][2];"
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
