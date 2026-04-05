# frozen_string_literal: true
# examples/generate_demo.rb
#
# Comprehensive generate block demonstration, combining generate-for,
# generate-if, const, attr, definition/instance, and more.
#
# Covered syntax:
# - generate_for with genvar loop variable and label
# - generate_if / generate_elif / generate_else with constant conditions
# - meta_param (Ruby kwargs) controlling generate bounds and conditions
# - Module instantiation inside generate-for (definition/instance pattern)
# - Genvar indexing for array port connections (chain[i], chain[i+1])
# - Local reg/wire/const declarations inside generate blocks
# - always_ff inside generate blocks
# - attr: hardware attributes on signals
#
# Run:
#   xmake rtl -f gen

$LOAD_PATH.unshift(File.join(__dir__, "..", "lib"))
require "rsv"
include RSV

# ---------- Sub-modules ----------

# A simple pipeline stage with meta-parameter width.
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

# ---------- Top module ----------

class GenerateDemo < ModuleDef
  def build(depth: 3, data_w: 8, mode: 0, n_ch: 4)
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

    # ---- Part 2: mode-dependent logic (Ruby if, since mode is a Ruby integer) ----
    flag = wire("flag", uint(8))

    if mode == 0
      flag <= data_in[0]
    elsif mode == 1
      flag <= ~data_in[0]
    else
      flag <= 0
    end

    # ---- Part 3: generate-for with definition/instance (meta-param sub-module) ----
    pipe_in = input("pipe_in", uint(data_w))
    pipe_out = output("pipe_out", uint(data_w))

    meta_chain = wire("meta_chain", arr(depth + 1, uint(data_w)))
    meta_chain[0] <= pipe_in

    stage_def = PipeStage.definition(width: data_w)

    generate_for("j", 0, depth, label: "gen_meta_stage") do |j|
      s = instance(stage_def, inst_name: "u_meta_stage")
      s.clk <= clk
      s.rst <= rst
      s.din <= meta_chain[j]
      meta_chain[j + 1] >= s.dout
    end

    pipe_out <= meta_chain[depth]

    # ---- Part 4: generate-if with const inside block ----
    status = wire("status", uint(8))

    if mode < 2
      status <= const("STATUS_VAL", uint(8, 0xAA))
    else
      status <= const("STATUS_VAL", uint(8, 0x55))
    end
  end
end

# ---------- Output ----------

def rtl_output_path(name)
  File.join(__dir__, "..", "build", "rtl", "#{name}.sv")
end

demo = GenerateDemo.new("generate_demo", depth: 3, data_w: 8, mode: 0, n_ch: 4)
demo.to_sv("-")
demo.to_sv(rtl_output_path("generate_demo"))

# Emit PipeStage dependency (meta-param definition)
PipeStage.send(:definition_handle_registry).each_value do |handle|
  handle.to_sv(rtl_output_path(handle.module_name))
end

warn "Written to #{rtl_output_path('generate_demo')}"
