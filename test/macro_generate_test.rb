# frozen_string_literal: true

require "minitest/autorun"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "rsv"

# ── 宏与generate测试 ────────────────────────────────────────────────────────
# 覆盖: sv_def/undef/ifdef/ifndef/elif/dref, generate_for/if/elif/else

class MacroGenerateTest < Minitest::Test
  # ── sv_def / sv_undef ──────────────────────────────────────────────────

  def test_sv_def_emits_define
    mod = module_class("DefTest") do
      sv_def "MY_MACRO", "42"
      sv_def "FLAG"
      output("dout", uint(8))
    end.new

    sv = mod.to_sv
    assert_includes sv, "`define MY_MACRO 42"
    assert_includes sv, "`define FLAG"
    refute_includes sv, "`define FLAG "
  end

  def test_sv_undef_emits_undef
    mod = module_class("UndefTest") do
      sv_def "TMP", "1"
      sv_undef "TMP"
    end.new

    sv = mod.to_sv
    assert_includes sv, "`undef TMP"
  end

  # ── sv_ifdef ───────────────────────────────────────────────────────────

  def test_sv_ifdef_endif
    mod = module_class("IfdefTest") do
      out = output("out", uint(8))
      w = wire("w", uint(8))
      sv_ifdef("SIM") do
        out <= w
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "`ifdef SIM"
    assert_includes sv, "assign out = w;"
    assert_includes sv, "`endif"
  end

  def test_sv_ifdef_else
    mod = module_class("IfdefElseTest") do
      out = output("out", uint(8))
      a = wire("a", uint(8))
      b = wire("b", uint(8))
      sv_ifdef("SIM") do
        out <= a
      end.sv_else_def do
        out <= b
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "`ifdef SIM"
    assert_includes sv, "assign out = a;"
    assert_includes sv, "`else"
    assert_includes sv, "assign out = b;"
    assert_includes sv, "`endif"
  end

  # ── sv_ifndef ──────────────────────────────────────────────────────────

  def test_sv_ifndef_with_elif
    mod = module_class("IfndefElifTest") do
      out = output("out", uint(8))
      a = wire("a", uint(8))
      b = wire("b", uint(8))
      c = wire("c", uint(8))
      sv_ifndef("SYNTHESIS") do
        out <= a
      end.sv_elif_def("FPGA") do
        out <= b
      end.sv_else_def do
        out <= c
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "`ifndef SYNTHESIS"
    assert_includes sv, "`elsif FPGA"
    assert_includes sv, "`else"
    assert_includes sv, "`endif"
  end

  def test_sv_ifndef_standalone
    mod = module_class("IfndefStandalone") do
      out = output("out", uint(8))
      w = wire("w", uint(8))
      sv_ifndef("GATE_SIM") do
        out <= w
      end
    end.new

    sv = mod.to_sv
    assert_includes sv, "`ifndef GATE_SIM"
    assert_includes sv, "assign out = w;"
    assert_includes sv, "`endif"
    refute_includes sv, "`else"
  end

  # ── sv_dref ────────────────────────────────────────────────────────────

  def test_sv_dref_macro_reference
    mod = module_class("DrefTest") do
      sv_def "WIDTH", "8"
      out = output("out", uint(8))
      w = wire("w", uint(8))
      out <= w + sv_dref("WIDTH")
    end.new

    sv = mod.to_sv
    assert_includes sv, "`define WIDTH 8"
    assert_includes sv, "`WIDTH"
  end

  # ── generate_for ───────────────────────────────────────────────────────

  def test_generate_for_with_local_and_always
    mod = module_class("GenForTest") {
      clk = input("clk", clock)
      rst = input("rst", reset)
      d = input("d", vec(4, uint(8)))
      q = output("q", vec(4, uint(8)))
      with_clk_and_rst(clk, rst)
      generate_for("i", 0, 4, label: "gen_pipe") do |i|
        r = reg("r", uint(8))
        always_ff { r <= d[i] }
        q[i] <= r
      end
    }.new

    sv = mod.to_sv
    assert_includes sv, "for (genvar i = 0; i < 4; i = i + 1) begin : gen_pipe"
    assert_includes sv, "logic [7:0] r;"
    assert_includes sv, "always_ff"
    assert_includes sv, "r <= d[i];"
    assert_includes sv, "assign q[i] = r;"
    assert_includes sv, "end"
  end

  def test_generate_for_without_label
    mod = module_class("GenForNoLabel") {
      d = input("d", vec(2, uint(4)))
      q = output("q", vec(2, uint(4)))
      generate_for("j", 0, 2) do |j|
        q[j] <= d[j]
      end
    }.new

    sv = mod.to_sv
    assert_includes sv, "for (genvar j = 0; j < 2; j = j + 1) begin"
    refute_includes sv, "begin :"
  end

  # ── generate_if ────────────────────────────────────────────────────────

  def test_generate_if_with_elsif_and_else
    mod = module_class("GenIfTest") {
      mode = const("MODE", uint(2, 1))
      a = input("a", uint(8))
      y = output("y", uint(8))
      generate_if(mode.eq(0), label: "m0") {
        y <= 0
      }.generate_elif(mode.eq(1), label: "m1") {
        y <= a
      }.generate_else(label: "mdef") {
        y <= 0xff
      }
    }.new

    sv = mod.to_sv
    assert_includes sv, "if (MODE == 0) begin : m0"
    assert_includes sv, "end else if (MODE == 1) begin : m1"
    assert_includes sv, "end else begin : mdef"
    assert_includes sv, "assign y = 8'd255;"
  end

  def test_generate_if_only_then
    mod = module_class("GenIfOnly") {
      en = const("EN", uint(1, 1))
      a = input("a", uint(8))
      y = output("y", uint(8))
      generate_if(en.eq(1), label: "gen_en") {
        y <= a
      }
    }.new

    sv = mod.to_sv
    assert_includes sv, "if (EN == 1) begin : gen_en"
    assert_includes sv, "assign y = a;"
    refute_includes sv, "else"
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
