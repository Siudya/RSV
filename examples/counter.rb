# frozen_string_literal: true
# examples/counter.rb
#
# Generates a parameterized synchronous counter with auto-generated reset logic.
# Run:  ruby examples/counter.rb

require "fileutils"

$LOAD_PATH.unshift(File.join(__dir__, "..", "lib"))
require "rsv"

counter = RSV::ModuleDef.new("Counter") do
  parameter "WIDTH", 8

  clk = input(uint("clk"))
  rst = input(uint("rst"))
  en = input(uint("en"))
  count = output(uint("count", width: "WIDTH"))

  countR = reg(uint("count_r", width: "WIDTH", init: "'0"))
  countNext = expr("count_next", countR + 1)

  assign_stmt(count, countR)

  with_clk_and_rst(clk, rst)
  always_ff do
    when_(en) do
      countR <= countNext
    end
  end
end

sv = counter.to_sv
puts sv

# Write the generated SV to build/rtl/counter.sv
outDir  = File.join(__dir__, "..", "build", "rtl")
FileUtils.mkdir_p(outDir)
outFile = File.join(outDir, "counter.sv")
File.write(outFile, sv + "\n")
warn "Written to #{outFile}"
