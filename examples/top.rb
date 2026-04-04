# frozen_string_literal: true
# examples/top.rb
#
# Demonstrates module instantiation by creating a top-level wrapper that
# instantiates two Counter modules with different widths.
# Run:  ruby examples/top.rb

$LOAD_PATH.unshift(File.join(__dir__, "..", "lib"))
require "rsv"

class Counter < RSV::ModuleDef
  def build(width: 8)
    parameter "WIDTH", width

    clk = input("clk", bit)
    rst = input("rst", bit)
    en = input("en", bit)
    count = output("count", uint("WIDTH"))

    count_r = reg("count_r", uint("WIDTH"), init: "'0")
    countNext = expr("count_next", count_r + 1)

    count <= count_r

    with_clk_and_rst(clk, rst)
    always_ff do
      svif(en) do
        count_r <= countNext
      end
    end
  end
end

class Top < RSV::ModuleDef
  def build
    clk = input("clk", bit)
    rst = input("rst", bit)
    enA = input("en_a", bit)
    enB = input("en_b", bit)
    countA = output("count_a", uint(8))
    countB = output("count_b", uint(16))

    counterA = Counter.new(inst_name: "u_counter_a", width: 8)
    counterA.clk <= clk
    counterA.rst <= rst
    counterA.en <= enA
    countA <= counterA.count

    counterB = Counter.new(inst_name: "u_counter_b", width: 16)
    counterB.clk <= clk
    counterB.rst <= rst
    counterB.en <= enB
    countB <= counterB.count
  end
end

top = Top.new
outFile = File.join(__dir__, "..", "build", "rtl", "top.sv")

top.to_sv("-")
top.to_sv(outFile)
warn "Written to #{outFile}"
