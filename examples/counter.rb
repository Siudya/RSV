# frozen_string_literal: true
# examples/counter.rb
#
# Generates a parameterized synchronous counter with auto-generated reset logic.
# Run:  ruby examples/counter.rb

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

counter = Counter.new(width: 8)
outFile = File.join(__dir__, "..", "build", "rtl", "counter.sv")

counter.to_sv("-")
counter.to_sv(outFile)
warn "Written to #{outFile}"
