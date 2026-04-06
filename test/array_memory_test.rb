# frozen_string_literal: true

require "minitest/autorun"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "rsv"

# ── 数组与存储测试 ───────────────────────────────────────────────────────────
# 覆盖: mem 形态声明, 索引赋值, 多维限制, fill/reverse, index type check

class ArrayMemoryTest < Minitest::Test
  def test_mem_declarations_emit_expected_sv_shapes
    mod = module_class("StorageShapes") do
      reg("cnt_mem_0", mem([2, 3, 4], uint(8)))
      reg("cnt_mem_1", mem(2, uint(8)))
    end.new

    expected = <<~SV.chomp
      module StorageShapes (
      );

        logic [7:0] cnt_mem_0[1:0][2:0][3:0];
        logic [7:0] cnt_mem_1[1:0];

      endmodule
    SV

    assert_equal expected, mod.to_sv
  end

  def test_indexed_memory_assignments_emit_expected_sv
    mod = module_class("IndexAssign") do
      clk = input("clk", bit)
      rst = input("rst", bit)
      idx = input("idx", uint(2))
      data = input("data", uint(8))
      mem_out = output("mem_out", uint(8))

      mem_reg = reg("mem_reg", mem([4], uint(8)))

      mem_out <= mem_reg[idx]

      with_clk_and_rst(clk, rst)
      always_ff do
        mem_reg[idx] <= data
      end
    end.new

    expected = <<~SV.chomp
      module IndexAssign (
        input  logic       clk,
        input  logic       rst,
        input  logic [1:0] idx,
        input  logic [7:0] data,
        output logic [7:0] mem_out
      );

        logic [7:0] mem_reg[3:0];

        assign mem_out = mem_reg[idx];

        always_ff @(posedge clk or posedge rst) begin
          mem_reg[idx] <= data;
        end

      endmodule
    SV

    assert_equal expected, mod.to_sv
  end

  def test_shaped_signals_only_allow_single_index_while_dimensions_remain
    error = assert_raises(ArgumentError) do
      module_class("BadShapeSelect") do
        mem_sig = wire("mem_sig", mem([2, 3], uint(8)))
        mem_sig[1, 0]
      end.new
    end

    assert_equal "array and memory selections only support a single index while dimensions remain", error.message
  end

  def test_nested_mem_flattens
    mod = module_class("NestedMem") do
      reg("buf", mem([2], mem([3], uint(8))))
    end.new

    sv = mod.to_sv
    assert_includes sv, "logic [7:0] buf[1:0][2:0];"
  end

  # ── mem index type checking ────────────────────────────────────────────

  def test_arr_mem_index_with_uint_works
    mod = module_class("IdxUint") do
      idx = input("idx", uint(2))
      dats = wire("dats", mem([4], uint(8)))
      out = output("out", uint(8))
      out <= dats[idx]
    end.new

    sv = mod.to_sv
    assert_includes sv, "assign out = dats[idx];"
  end

  def test_mem_index_with_literal_works
    mod = module_class("IdxLit") do
      dats = wire("dats", mem([4], uint(8)))
      out = output("out", uint(8))
      out <= dats[2]
    end.new

    sv = mod.to_sv
    assert_includes sv, "assign out = dats[2];"
  end

  def test_mem_index_with_sint_raises
    error = assert_raises(ArgumentError) do
      module_class("IdxSint") do
        idx = input("idx", sint(2))
        dats = wire("dats", mem([4], uint(8)))
        dats[idx]
      end.new
    end

    assert_includes error.message, "unsigned"
  end

  # ── reverse ────────────────────────────────────────────────────────────

  def test_mem_reverse
    mod = module_class("MemReverse") do
      pos = wire("pos", mem(4, uint(8)))
      pos.reverse
    end.new

    sv = mod.to_sv
    assert_includes sv, "logic [7:0] pos[3:0]"
    assert_includes sv, "logic [7:0] pos_reverse[3:0]"
    assert_includes sv, "for (int _rv_i = 0; _rv_i < 4; _rv_i = _rv_i + 1) begin"
    assert_includes sv, "pos_reverse[_rv_i] = pos[3 - _rv_i];"
  end

  def test_bundle_mem_reverse
    pxl_cls = Class.new(RSV::BundleDef) do
      define_singleton_method(:name) { "Pixel" }
      def build
        input("r", uint(8))
        input("g", uint(8))
      end
    end

    mod = module_class("BundleMemReverse") do
      pxls = wire("pxls", mem(3, pxl_cls.new))
      pxls.reverse
    end.new

    sv = mod.to_sv
    assert_includes sv, "logic [7:0] pxls_r_reverse[2:0]"
    assert_includes sv, "logic [7:0] pxls_g_reverse[2:0]"
    assert_includes sv, "pxls_r_reverse[_rv_i] = pxls_r[2 - _rv_i];"
    assert_includes sv, "pxls_g_reverse[_rv_i] = pxls_g[2 - _rv_i];"
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
