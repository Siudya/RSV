# frozen_string_literal: true

require "minitest/autorun"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "rsv"

class NewTypesDslTest < Minitest::Test
  # ── bits & uint alias ─────────────────────────────────────────────────────

  def test_bits_is_equivalent_to_uint
    mod = module_class("BitsAlias") do
      input("a", bits(8))
      output("b", uint(8))
    end.new

    sv = mod.to_sv
    assert_includes sv, "logic [7:0] a"
    assert_includes sv, "logic [7:0] b"
  end

  # ── sint ──────────────────────────────────────────────────────────────────

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

  # ── as_sint ───────────────────────────────────────────────────────────────

  def test_as_sint_emits_dollar_signed
    mod = module_class("AsSintTop") do
      a = input("a", uint(8))
      b = output("b", sint(8))
      b <= a.as_sint
    end.new

    sv = mod.to_sv
    assert_includes sv, "assign b = $signed(a);"
  end

  # ── clock type ────────────────────────────────────────────────────────────

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

  # ── reset type ────────────────────────────────────────────────────────────

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

  # ── arr/mem nesting flattening ────────────────────────────────────────────

  def test_nested_arr_flattens
    mod = module_class("NestedArr") do
      wire("x", arr([2], arr([3], arr([4], uint(8)))))
    end.new

    expected_mod = module_class("NestedArr2") do
      wire("x", arr([2, 3, 4], uint(8)))
    end.new

    assert_equal expected_mod.to_sv.gsub("NestedArr2", "NestedArr"), mod.to_sv
  end

  def test_nested_mem_flattens
    mod = module_class("NestedMem") do
      wire("x", mem([2], mem([3], mem([4], uint(8)))))
    end.new

    expected_mod = module_class("NestedMem2") do
      wire("x", mem([2, 3, 4], uint(8)))
    end.new

    assert_equal expected_mod.to_sv.gsub("NestedMem2", "NestedMem"), mod.to_sv
  end

  # ── complex expression test ───────────────────────────────────────────────

  def test_complex_expression_translates_correctly
    mod = module_class("ComplexExpr") do
      a = input("a", uint(8))
      b = input("b", uint(8))
      c = input("c", uint(8))
      d = input("d", uint(8))
      e = input("e", uint(8))
      out = output("out", uint(8))

      out <= (a + b) * (c + d) / e
    end.new

    sv = mod.to_sv
    assert_includes sv, "assign out = (a + b) * (c + d) / e;"
  end

  # ── mux ternary ──────────────────────────────────────────────────────────

  def test_mux_emits_ternary
    mod = module_class("MuxTop") do
      sel = input("sel", bit)
      a = input("a", uint(8))
      b = input("b", uint(8))
      out = output("out", uint(8))

      out <= mux(sel, a, b)
    end.new

    sv = mod.to_sv
    assert_includes sv, "assign out = sel ? a : b;"
  end

  def test_mux_nested
    mod = module_class("MuxNested") do
      s0 = input("s0", bit)
      s1 = input("s1", bit)
      a = input("a", uint(8))
      b = input("b", uint(8))
      c = input("c", uint(8))
      out = output("out", uint(8))

      out <= mux(s0, mux(s1, a, b), c)
    end.new

    sv = mod.to_sv
    assert_includes sv, "assign out = s0 ? (s1 ? a : b) : c;"
  end

  # ── mux1h ────────────────────────────────────────────────────────────────

  def test_mux1h_emits_unique_casez
    mod = module_class("Mux1hTop") do
      sel = input("sel", uint(3))
      dats = input("dats", mem([3], uint(8)))
      out = wire("out", uint(8))

      always_comb do
        out <= mux1h(sel, dats)
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "always_comb begin"
    assert_includes sv, "unique casez (sel)"
    assert_includes sv, "3'b001: out = dats[0];"
    assert_includes sv, "3'b010: out = dats[1];"
    assert_includes sv, "3'b100: out = dats[2];"
    assert_includes sv, "default: out = 8'd0;"
    assert_includes sv, "endcase"
    refute_includes sv, "?"
  end

  def test_mux1h_outside_always_raises
    assert_raises(ArgumentError) do
      module_class("Mux1hBad") do
        sel = input("sel", uint(3))
        dats = input("dats", mem([3], uint(8)))
        out = wire("out", uint(8))
        out <= mux1h(sel, dats)
      end.new
    end
  end

  # ── muxp ─────────────────────────────────────────────────────────────────

  def test_muxp_emits_priority_casez
    mod = module_class("MuxpTop") do
      sel = input("sel", uint(3))
      dats = input("dats", mem([3], uint(8)))
      out = wire("out", uint(8))

      always_comb do
        out <= muxp(sel, dats)
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "always_comb begin"
    assert_includes sv, "priority casez (sel)"
    # lsb_first (default): sel[0] highest priority, checked first
    assert_includes sv, "3'b??1: out = dats[0];"
    assert_includes sv, "3'b?10: out = dats[1];"
    assert_includes sv, "3'b100: out = dats[2];"
    # default = lowest priority data
    assert_includes sv, "default: out = dats[2];"
    assert_includes sv, "endcase"
  end

  def test_muxp_msb_first
    mod = module_class("MuxpMsb") do
      sel = input("sel", uint(3))
      dats = input("dats", mem([3], uint(8)))
      out = wire("out", uint(8))

      always_comb do
        out <= muxp(sel, dats, lsb_first: false)
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "priority casez (sel)"
    # msb_first: sel[2] highest priority, checked first
    assert_includes sv, "3'b1??: out = dats[2];"
    assert_includes sv, "3'b01?: out = dats[1];"
    assert_includes sv, "3'b001: out = dats[0];"
    # default = lowest priority data
    assert_includes sv, "default: out = dats[0];"
  end

  def test_muxp_outside_always_raises
    assert_raises(ArgumentError) do
      module_class("MuxpBad") do
        sel = input("sel", uint(3))
        dats = input("dats", mem([3], uint(8)))
        out = wire("out", uint(8))
        out <= muxp(sel, dats)
      end.new
    end
  end

  # ── cat ───────────────────────────────────────────────────────────────────

  def test_cat_emits_concatenation
    mod = module_class("CatTest") do
      a = input("a", uint(4))
      b = input("b", uint(4))
      c = input("c", uint(8))
      out = output("out", uint(16))
      out <= cat(a, b, c)
    end.new

    sv = mod.to_sv
    assert_includes sv, "assign out = {a, b, c};"
  end

  def test_cat_inside_always_comb
    mod = module_class("CatComb") do
      a = input("a", uint(4))
      b = input("b", uint(4))
      out = wire("out", uint(8))
      always_comb do
        out <= cat(a, b)
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "out = {a, b};"
  end

  # ── fill ──────────────────────────────────────────────────────────────────

  def test_fill_emits_replication
    mod = module_class("FillTest") do
      a = input("a", uint(4))
      out = output("out", uint(16))
      out <= fill(4, a)
    end.new

    sv = mod.to_sv
    assert_includes sv, "assign out = {4{a}};"
  end

  def test_fill_inside_always_comb
    mod = module_class("FillComb") do
      a = input("a", uint(1))
      out = wire("out", uint(8))
      always_comb do
        out <= fill(8, a)
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "out = {8{a}};"
  end

  # ── index type checking ────────────────────────────────────────────────

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

  def test_arr_mem_index_with_literal_works
    mod = module_class("IdxLit") do
      dats = wire("dats", arr([4], uint(8)))
      out = output("out", uint(8))
      out <= dats[2]
    end.new

    sv = mod.to_sv
    assert_includes sv, "assign out = dats[2];"
  end

  def test_arr_mem_index_with_sint_raises
    error = assert_raises(ArgumentError) do
      module_class("IdxSint") do
        idx = input("idx", sint(2))
        dats = wire("dats", mem([4], uint(8)))
        dats[idx]
      end.new
    end

    assert_includes error.message, "unsigned"
  end

  # ── runtime arithmetic on non-hardware data types ─────────────────────

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

  # ── arr/mem interleave ────────────────────────────────────────────────

  def test_arr_mem_interleave
    mod = module_class("Interleave") do
      wire("x", mem([2], arr([3], mem([4], uint(8)))))
    end.new

    sv = mod.to_sv
    assert_includes sv, "logic [2:0][7:0] x[1:0][3:0]"
  end

  # ── svcase ─────────────────────────────────────────────────────────────────

  def test_svcase_emits_case
    mod = module_class("CaseTest") do
      sel = input("sel", uint(2))
      out = wire("out", uint(8))

      always_comb do
        svcase(sel) do
          is(0) { out <= 0x10 }
          is(1) { out <= 0x20 }
          is(2) { out <= 0x30 }
          fallin { out <= 0xFF }
        end
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "case (sel)"
    assert_includes sv, "0: begin"
    assert_includes sv, "out = 8'd16;"
    assert_includes sv, "1: begin"
    assert_includes sv, "2: begin"
    assert_includes sv, "default: begin"
    assert_includes sv, "out = 8'd255;"
    assert_includes sv, "endcase"
  end

  def test_svcasez_emits_casez
    mod = module_class("CasezTest") do
      sel = input("sel", uint(4))
      out = wire("out", uint(8))

      always_comb do
        svcasez(sel) do
          is(0b0001) { out <= 0xA }
          is(0b0010) { out <= 0xB }
          fallin { out <= 0 }
        end
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "casez (sel)"
    assert_includes sv, "endcase"
  end

  def test_svcase_unique
    mod = module_class("UniqueCase") do
      sel = input("sel", uint(2))
      out = wire("out", uint(8))

      always_comb do
        svcase(sel, unique: true) do
          is(0) { out <= 1 }
          is(1) { out <= 2 }
          fallin { out <= 0 }
        end
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "unique case (sel)"
    assert_includes sv, "endcase"
  end

  def test_svcase_priority
    mod = module_class("PriorityCase") do
      sel = input("sel", uint(2))
      out = wire("out", uint(8))

      always_comb do
        svcase(sel, priority: true) do
          is(0) { out <= 1 }
          fallin { out <= 0 }
        end
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "priority case (sel)"
  end

  def test_svcasez_unique
    mod = module_class("UniqueCasez") do
      sel = input("sel", uint(4))
      out = wire("out", uint(8))

      always_comb do
        svcasez(sel, unique: true) do
          is(0b0001) { out <= 1 }
          fallin { out <= 0 }
        end
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "unique casez (sel)"
  end

  def test_svcasez_wildcard
    mod = module_class("CasezWild") do
      sel = input("sel", uint(4))
      out = wire("out", uint(8))

      always_comb do
        svcasez(sel) do
          is("4'b1??0") { out <= 0xA }
          is("4'b??01") { out <= 0xB }
          fallin { out <= 0 }
        end
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "casez (sel)"
    assert_includes sv, "4'b1??0: begin"
    assert_includes sv, "4'b??01: begin"
  end

  def test_svcase_multi_val_branch
    mod = module_class("MultiVal") do
      sel = input("sel", uint(3))
      out = wire("out", uint(8))

      always_comb do
        svcase(sel) do
          is(0, 1) { out <= 0xAA }
          is(2, 3) { out <= 0xBB }
          fallin { out <= 0 }
        end
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "case (sel)"
    assert_includes sv, "0, 1: begin"
    assert_includes sv, "2, 3: begin"
  end

  def test_svcase_in_always_ff
    mod = module_class("CaseFF") do
      clk = input("clk", clock)
      rst = input("rst", reset)
      sel = input("sel", uint(2))
      r = reg("r", uint(8), init: 0)

      with_clk_and_rst(clk, rst)
      always_ff do
        svcase(sel) do
          is(0) { r <= 0x10 }
          is(1) { r <= 0x20 }
          fallin { r <= 0 }
        end
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "always_ff @(posedge clk"
    assert_includes sv, "case (sel)"
    assert_includes sv, "r <= 8'd16;"
    assert_includes sv, "endcase"
  end

  # ── svif unique/priority ─────────────────────────────────────────────────

  def test_svif_unique
    mod = module_class("UniqueIf") do
      a = input("a", uint(2))
      out = wire("out", uint(8))

      always_comb do
        svif(a.eq(0), unique: true) { out <= 1 }
        .svelif(a.eq(1)) { out <= 2 }
        .svelse { out <= 0 }
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "unique if (a == 2'd0) begin"
    assert_includes sv, "end else if (a == 2'd1) begin"
    assert_includes sv, "end else begin"
  end

  def test_svif_priority
    mod = module_class("PriorityIf") do
      a = input("a", uint(2))
      out = wire("out", uint(8))

      always_comb do
        svif(a.eq(0), priority: true) { out <= 1 }
        .svelse { out <= 0 }
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "priority if (a == 2'd0) begin"
  end

  # ── log2ceil ───────────────────────────────────────────────────────────────

  def test_log2ceil
    assert_equal 0, RSV.log2ceil(1)
    assert_equal 1, RSV.log2ceil(2)
    assert_equal 2, RSV.log2ceil(3)
    assert_equal 2, RSV.log2ceil(4)
    assert_equal 3, RSV.log2ceil(5)
    assert_equal 3, RSV.log2ceil(8)
    assert_equal 4, RSV.log2ceil(9)
    assert_equal 4, RSV.log2ceil(16)
    assert_equal 5, RSV.log2ceil(17)
    assert_raises(ArgumentError) { RSV.log2ceil(0) }
    assert_raises(ArgumentError) { RSV.log2ceil(-1) }
  end

  def test_log2ceil_in_build
    mod = module_class("Log2CeilMod") do
      w = log2ceil(8 + 1)   # 4 bits for 0..8
      _cnt = wire("cnt", uint(w))
    end.new
    sv = mod.to_sv
    assert_includes sv, "logic [3:0] cnt"
  end

  # ── pop_count ──────────────────────────────────────────────────────────────

  def test_pop_count_basic
    mod = module_class("PopCntBasic") do
      vec = input("vec", uint(8))
      cnt = wire("cnt", uint(log2ceil(8 + 1)))

      always_comb do
        cnt <= pop_count(vec)
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "logic [3:0] cnt"
    assert_includes sv, "cnt = 4'd0;"
    assert_includes sv, "for (int _pc_i = 0; _pc_i < 8; _pc_i = _pc_i + 1) begin"
    assert_includes sv, "cnt = cnt + {{3{1'b0}}, vec[_pc_i]};"
    assert_includes sv, "end"
  end

  def test_pop_count_4bit
    mod = module_class("PopCnt4") do
      vec = input("vec", uint(4))
      cnt = wire("cnt", uint(log2ceil(4 + 1)))

      always_comb do
        cnt <= pop_count(vec)
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "logic [2:0] cnt"
    assert_includes sv, "cnt = 3'd0;"
    assert_includes sv, "for (int _pc_i = 0; _pc_i < 4; _pc_i = _pc_i + 1) begin"
    assert_includes sv, "cnt = cnt + {{2{1'b0}}, vec[_pc_i]};"
  end

  def test_pop_count_rejects_always_ff
    assert_raises(ArgumentError) do
      module_class("PopCntFF") do
        clk = input("clk", clock)
        rst = input("rst", reset)
        vec = input("vec", uint(4))
        cnt = reg("cnt", uint(3), init: 0)

        with_clk_and_rst(clk, rst)
        always_ff do
          cnt <= pop_count(vec)
        end
      end.new
    end
  end

  def test_pop_count_rejects_module_level
    assert_raises(ArgumentError) do
      module_class("PopCntTop") do
        vec = input("vec", uint(4))
        cnt = wire("cnt", uint(3))
        cnt <= pop_count(vec)
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
