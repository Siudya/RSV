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

$LOAD_PATH.unshift(File.join(__dir__, '..', 'lib'))
require 'rsv'
include RSV

# ---------- Sub-modules ----------

# A simple pipeline stage with meta-parameter width.
class PipeStage < ModuleDef
  def build(width: 8)
    let :clk, input(clock)
    let :rst, input(reset)
    let :din, input(uint(width))
    let :dout, output(uint(width))
    let :r, reg(uint(width), init: 0)
    dout <= r
    with_clk_and_rst(clk, rst)
    always_ff { r <= din }
  end
end

# ---------- Top module ----------

class GenerateDemo < ModuleDef
  def build(depth: 3, data_w: 8, mode: 0, n_ch: 4)
    let :clk, input(clock)
    let :rst, input(reset)

    # ---- Part 1: generate-for with inline logic and genvar indexing ----
    let :data_in, input(vec(n_ch, uint(8)))
    let :data_out, output(vec(n_ch, uint(8))), attr: { 'keep' => nil }

    generate_for('i', 0, n_ch, label: 'gen_reg') do |i|
      r = reg('stage_r', uint(8), init: 0)
      with_clk_and_rst(clk, rst)
      always_ff do
        r <= data_in[i]
      end
      data_out[i] <= r
    end

    # ---- Part 2: mode-dependent logic (Ruby if, since mode is a Ruby integer) ----
    let :flag, wire(uint(8))

    flag <= if mode == 0
              data_in[0]
            elsif mode == 1
              ~data_in[0]
            else
              0
            end

    # ---- Part 3: generate-for with definition/instance (meta-param sub-module) ----
    let :pipe_in, input(uint(data_w))
    let :pipe_out, output(uint(data_w))

    let :meta_chain, wire(vec(depth + 1, uint(data_w)))
    meta_chain[0] <= pipe_in

    stage_def = PipeStage.definition(width: data_w)

    generate_for('j', 0, depth, label: 'gen_meta_stage') do |j|
      s = instance(stage_def, inst_name: 'u_meta_stage')
      s.clk <= clk
      s.rst <= rst
      s.din <= meta_chain[j]
      meta_chain[j + 1] >= s.dout
    end

    pipe_out <= meta_chain[depth]

    # ---- Part 4: use meta params to prune the codes ----
    let :status, wire(uint(8))

    status <= if mode < 2
                const('STATUS_VAL', uint(8, 0xAA))
              else
                const('STATUS_VAL', uint(8, 0x55))
              end
  end
end

# ---------- Output ----------

demo = GenerateDemo.new('generate_demo', depth: 3, data_w: 8, mode: 0, n_ch: 4)

RSV::App.main(demo)
