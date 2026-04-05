# frozen_string_literal: true
# examples/generate_demo.rb
#
# Demonstrates generate-for and generate-if blocks.
#
# Covered syntax:
# - generate_for with genvar loop variable and label
# - generate_if / generate_elif / generate_else with constant conditions
# - Local reg/wire declarations inside generate blocks
# - always_ff inside generate blocks
# - Module instantiation inside generate-for using definition/instance
# - Genvar indexing for port connections (chain[i], chain[i+1])
#
# Run:
#   ruby examples/generate_demo.rb

$LOAD_PATH.unshift(File.join(__dir__, "..", "lib"))
require "rsv"
include RSV

# A simple pipeline stage module used as the generate-for instantiation target.
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

class GenerateDemo < ModuleDef
  def build(width: 4, depth: 3, pipe_w: 8)
    clk = input("clk", clock)
    rst = input("rst", reset)
    mode = const("MODE", uint(2, 1))
    data_in = input("data_in", arr(width, uint(8)))
    data_out = output("data_out", arr(width, uint(8)))

    # --- generate for: inline pipeline registers ---
    generate_for("i", 0, width, label: "gen_pipe") do |i|
      r = reg("pipe_r", uint(8))
      with_clk_and_rst(clk, rst)
      always_ff do
        r <= data_in[i]
      end
      data_out[i] <= r
    end

    # --- generate if: conditional logic based on constant ---
    flag = wire("flag", uint(8))
    generate_if(mode.eq(0), label: "gen_mode") {
      flag <= 0
    }.generate_elif(mode.eq(1), label: "gen_mode1") {
      flag <= data_in[0]
    }.generate_else(label: "gen_default") {
      flag <= data_in[1]
    }

    # --- generate for: instantiate pipeline stages with definition/instance ---
    pipe_in = input("pipe_in", uint(pipe_w))
    pipe_out = output("pipe_out", uint(pipe_w))

    chain = wire("chain", arr(depth + 1, uint(pipe_w)))
    chain[0] <= pipe_in

    stage_def = PipeStage.definition(width: pipe_w)

    generate_for("k", 0, depth, label: "gen_stage") do |k|
      s = instance(stage_def, inst_name: "u_stage")
      s.clk <= clk
      s.rst <= rst
      s.din <= chain[k]
      chain[k + 1] >= s.dout
    end

    pipe_out <= chain[depth]
  end
end

def rtl_output_path(name)
  File.join(__dir__, "..", "build", "rtl", "#{name}.sv")
end

demo = GenerateDemo.new("generate_demo")
demo.to_sv("-")
demo.to_sv(rtl_output_path("generate_demo"))

# Also emit the PipeStage dependency
stage_defs = PipeStage.instance_variable_get(:@definition_handle_registry)&.values || []
stage_defs.each do |defn|
  defn.to_sv(rtl_output_path(defn.module_name))
end

warn "Written to #{rtl_output_path('generate_demo')}"
