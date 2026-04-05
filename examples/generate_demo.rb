# frozen_string_literal: true
# examples/generate_demo.rb
#
# Demonstrates generate-for and generate-if blocks.
#
# Run:
#   ruby examples/generate_demo.rb

$LOAD_PATH.unshift(File.join(__dir__, "..", "lib"))
require "rsv"
include RSV

class GenerateDemo < ModuleDef
  def build(width: 4)
    clk = input("clk", clock)
    rst = input("rst", reset)
    mode = const("MODE", uint(2, 1))
    data_in = input("data_in", arr(width, uint(8)))
    data_out = output("data_out", arr(width, uint(8)))

    # generate for: pipeline registers
    generate_for("i", 0, width, label: "gen_pipe") do |i|
      r = reg("pipe_r", uint(8))
      with_clk_and_rst(clk, rst)
      always_ff do
        r <= data_in[i]
      end
      data_out[i] <= r
    end

    # generate if: conditional logic based on constant
    flag = wire("flag", uint(8))
    generate_if(mode.eq(0), label: "gen_mode") {
      flag <= 0
    }.generate_elif(mode.eq(1), label: "gen_mode1") {
      flag <= data_in[0]
    }.generate_else(label: "gen_default") {
      flag <= data_in[1]
    }
  end
end

output_path = File.join(__dir__, "..", "build", "rtl", "generate_demo.sv")

demo = GenerateDemo.new("generate_demo")
demo.to_sv("-")
demo.to_sv(output_path)
warn "Written to #{output_path}"
