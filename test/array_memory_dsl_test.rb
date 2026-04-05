# frozen_string_literal: true

require "minitest/autorun"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "rsv"

class ArrayMemoryDslTest < Minitest::Test
  def test_arr_mem_and_mixed_declarations_emit_expected_sv_shapes
    mod = module_class("StorageShapes") do
      reg("cnt_arr_0", arr([2, 3, 4], uint(8)))
      reg("cnt_arr_1", arr(2, uint(8)))
      reg("cnt_mem_0", mem([2, 3, 4], uint(8)))
      reg("cnt_mem_1", mem(2, uint(8)))
      reg("cnt_dat", mem([1, 2, 3], arr([4, 5, 6], uint(8))))
    end.new

    expected = <<~SV.chomp
      module StorageShapes (
      );

        logic [1:0][2:0][3:0][7:0] cnt_arr_0;
        logic [1:0][7:0]           cnt_arr_1;
        logic [7:0]                cnt_mem_0[1:0][2:0][3:0];
        logic [7:0]                cnt_mem_1[1:0];
        logic [3:0][4:0][5:0][7:0] cnt_dat[0:0][1:0][2:0];

      endmodule
    SV

    assert_equal expected, mod.to_sv
  end

  def test_indexed_array_and_memory_assignments_emit_expected_sv
    mod = module_class("IndexAssign") do
      clk = input("clk", bit)
      rst = input("rst", bit)
      idx = input("idx", uint(2))
      data = input("data", uint(8))
      arr_out = output("arr_out", uint(8))
      mem_out = output("mem_out", uint(8))

      arr_reg = reg("arr_reg", arr([4], uint(8)))
      mem_reg = reg("mem_reg", mem([4], uint(8)))

      arr_out <= arr_reg[idx]
      mem_out <= mem_reg[idx]

      with_clk_and_rst(clk, rst)
      always_ff do
        arr_reg[idx] <= data
        mem_reg[idx] <= data
      end
    end.new

    expected = <<~SV.chomp
      module IndexAssign (
        input  logic       clk,
        input  logic       rst,
        input  logic [1:0] idx,
        input  logic [7:0] data,
        output logic [7:0] arr_out,
        output logic [7:0] mem_out
      );

        logic [3:0][7:0] arr_reg;
        logic [7:0]      mem_reg[3:0];

        assign arr_out = arr_reg[idx];
        assign mem_out = mem_reg[idx];

        always_ff @(posedge clk or posedge rst) begin
          arr_reg[idx] <= data;
          mem_reg[idx] <= data;
        end

      endmodule
    SV

    assert_equal expected, mod.to_sv
  end

  def test_shaped_signals_only_allow_single_index_while_dimensions_remain
    error = assert_raises(ArgumentError) do
      module_class("BadShapeSelect") do
        packed = wire("packed", arr([2, 3], uint(8)))
        packed[1, 0]
      end.new
    end

    assert_equal "array and memory selections only support a single index while dimensions remain", error.message
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
