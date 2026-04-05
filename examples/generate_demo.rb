# frozen_string_literal: true
# examples/generate_demo.rb
#
# Comprehensive generate block demonstration, combining generate-for,
# generate-if, sv_param, const, attr, definition/instance, and more.
#
# Covered syntax:
# - generate_for with genvar loop variable and label
# - generate_if / generate_elif / generate_else with constant conditions
# - sv_param as generate-for loop bound and generate-if condition
# - sv_param passed through to sub-module instances inside generate-for
# - Module instantiation inside generate-for (definition/instance pattern)
# - Curried sv_param sub-module instantiation inside generate-for
# - Genvar indexing for array port connections (chain[i], chain[i+1])
# - Local reg/wire/const declarations inside generate blocks
# - always_ff inside generate blocks
# - attr: hardware attributes on signals
#
# Run:
#   ruby examples/generate_demo.rb

$LOAD_PATH.unshift(File.join(__dir__, "..", "lib"))
require "rsv"
include RSV

# ---------- Sub-modules ----------

# A simple pipeline stage with meta-parameter width (no sv_param).
class PipeStage < ModuleDef
  def build(width: 8)
    clk = input("clk", clock)
    rst = input("rst", reset)
    din = input("din", uint(width))
    dout = output("dout", uint(width))
    r = reg("r", uint(width), init: 0)
    dout <= r
    with_clk_and_rst(clk, rst)
    always_ff { r <= din }
  end
end

# A pipeline stage with sv_param width.
class SvPipeStage < ModuleDef
  W = sv_param("W", 8)

  def build
    clk = input("clk", clock)
    rst = input("rst", reset)
    din = input("din", uint(W))
    dout = output("dout", uint(W))
    r = reg("r", uint(W), init: 0)
    dout <= r
    with_clk_and_rst(clk, rst)
    always_ff { r <= din }
  end
end

# ---------- Top module ----------

class GenerateDemo < ModuleDef
  DEPTH = sv_param("DEPTH", 3)
  DATA_W = sv_param("DATA_W", 8)
  MODE = sv_param("MODE", 0)

  def build(n_ch: 4)
    clk = input("clk", clock)
    rst = input("rst", reset)

    # ---- Part 1: generate-for with inline logic and genvar indexing ----
    data_in = input("data_in", arr(n_ch, uint(8)))
    data_out = output("data_out", arr(n_ch, uint(8)), attr: { "keep" => nil })

    generate_for("i", 0, n_ch, label: "gen_reg") do |i|
      r = reg("stage_r", uint(8), init: 0)
      with_clk_and_rst(clk, rst)
      always_ff do
        r <= data_in[i]
      end
      data_out[i] <= r
    end

    # ---- Part 2: generate-if controlled by sv_param ----
    flag = wire("flag", uint(8))

    generate_if(MODE.eq(0), label: "gen_bypass") {
      flag <= data_in[0]
    }.generate_elif(MODE.eq(1), label: "gen_invert") {
      flag <= ~data_in[0]
    }.generate_else(label: "gen_zero") {
      flag <= 0
    }

    # ---- Part 3: generate-for with definition/instance (meta-param sub-module) ----
    pipe_in = input("pipe_in", uint(8))
    pipe_out = output("pipe_out", uint(8))

    meta_chain = wire("meta_chain", arr(DEPTH + 1, uint(8)))
    meta_chain[0] <= pipe_in

    stage_def = PipeStage.definition(width: 8)

    generate_for("j", 0, DEPTH, label: "gen_meta_stage") do |j|
      s = instance(stage_def, inst_name: "u_meta_stage")
      s.clk <= clk
      s.rst <= rst
      s.din <= meta_chain[j]
      meta_chain[j + 1] >= s.dout
    end

    pipe_out <= meta_chain[DEPTH]

    # ---- Part 4: generate-for with sv_param sub-module (curried instantiation) ----
    sv_in = input("sv_in", uint(DATA_W))
    sv_out = output("sv_out", uint(DATA_W))

    sv_chain = wire("sv_chain", arr(DEPTH + 1, uint(DATA_W)))
    sv_chain[0] <= sv_in

    generate_for("k", 0, DEPTH, label: "gen_sv_stage") do |k|
      s = SvPipeStage.new("sv_pipe_stage").(W: DATA_W).()
      s.clk <= clk
      s.rst <= rst
      s.din <= sv_chain[k]
      sv_chain[k + 1] >= s.dout
    end

    sv_out <= sv_chain[DEPTH]

    # ---- Part 5: generate-if with const inside block ----
    status = wire("status", uint(8))

    generate_if(MODE.lt(2), label: "gen_status_lo") {
      c = const("STATUS_VAL", uint(8, 0xAA))
      status <= c
    }.generate_else(label: "gen_status_hi") {
      c = const("STATUS_VAL", uint(8, 0x55))
      status <= c
    }
  end
end

# ---------- Output ----------

def rtl_output_path(name)
  File.join(__dir__, "..", "build", "rtl", "#{name}.sv")
end

demo = GenerateDemo.new("generate_demo").().(n_ch: 4)
demo.to_sv("-")
demo.to_sv(rtl_output_path("generate_demo"))

# Emit PipeStage dependency (meta-param definition)
PipeStage.send(:definition_handle_registry).each_value do |handle|
  handle.to_sv(rtl_output_path(handle.module_name))
end

# Emit SvPipeStage dependency (sv_param definition)
SvPipeStage.send(:definition_handle_registry).each_value do |handle|
  handle.definition.to_sv(rtl_output_path(handle.module_name))
end

warn "Written to #{rtl_output_path('generate_demo')}"
