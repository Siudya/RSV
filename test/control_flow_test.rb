# frozen_string_literal: true

require "minitest/autorun"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "rsv"

# ── 控制流测试 ───────────────────────────────────────────────────────────────
# 覆盖: svif/svelif/svelse (unique/priority),
#       svcase/svcasez/svcasex (unique/priority/wildcard/multi-val)

class ControlFlowTest < Minitest::Test
  # ── svcase ──────────────────────────────────────────────────────────────

  def test_svcase_emits_case
    mod = module_class("CaseTest") do
      sel = iodecl("sel", input(uint(2)))
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
      sel = iodecl("sel", input(uint(4)))
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

  # ── svcasex ─────────────────────────────────────────────────────────────

  def test_svcasex_emits_casex
    mod = module_class("CasexTest") do
      sel = iodecl("sel", input(uint(4)))
      out = wire("out", uint(8))

      always_comb do
        svcasex(sel) do
          is("4'bxx01") { out <= 0xA }
          is("4'bxx10") { out <= 0xB }
          fallin { out <= 0 }
        end
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "casex (sel)"
    assert_includes sv, "4'bxx01: begin"
    assert_includes sv, "4'bxx10: begin"
    assert_includes sv, "default: begin"
    assert_includes sv, "endcase"
  end

  # ── unique / priority case ─────────────────────────────────────────────

  def test_svcase_unique
    mod = module_class("UniqueCase") do
      sel = iodecl("sel", input(uint(2)))
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
      sel = iodecl("sel", input(uint(2)))
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
      sel = iodecl("sel", input(uint(4)))
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

  # ── casez wildcard / multi-value ───────────────────────────────────────

  def test_svcasez_wildcard
    mod = module_class("CasezWild") do
      sel = iodecl("sel", input(uint(4)))
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
      sel = iodecl("sel", input(uint(3)))
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

  # ── case in always_ff ──────────────────────────────────────────────────

  def test_svcase_in_always_ff
    mod = module_class("CaseFF") do
      clk = iodecl("clk", input(clock))
      rst = iodecl("rst", input(reset))
      sel = iodecl("sel", input(uint(2)))
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

  # ── svif unique/priority ───────────────────────────────────────────────

  def test_svif_unique
    mod = module_class("UniqueIf") do
      a = iodecl("a", input(uint(2)))
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
      a = iodecl("a", input(uint(2)))
      out = wire("out", uint(8))

      always_comb do
        svif(a.eq(0), priority: true) { out <= 1 }
        .svelse { out <= 0 }
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "priority if (a == 2'd0) begin"
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
