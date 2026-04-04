# frozen_string_literal: true
# examples/top.rb
#
# Demonstrates module instantiation by creating a top-level wrapper that
# instantiates two Counter modules with different widths.
# Run:  ruby examples/top.rb

require "fileutils"

$LOAD_PATH.unshift(File.join(__dir__, "..", "lib"))
require "rsv"

top = RSV::ModuleDef.new("Top") do
  clk = input(uint("clk"))
  rst = input(uint("rst"))
  enA = input(uint("en_a"))
  enB = input(uint("en_b"))
  countA = output(uint("count_a", width: 8))
  countB = output(uint("count_b", width: 16))

  instantiate "Counter", "u_counter_a",
    params:      { "WIDTH" => 8 },
    connections: {
      "clk"   => clk,
      "rst"   => rst,
      "en"    => enA,
      "count" => countA
    }

  instantiate "Counter", "u_counter_b",
    params:      { "WIDTH" => 16 },
    connections: {
      "clk"   => clk,
      "rst"   => rst,
      "en"    => enB,
      "count" => countB
    }
end

sv = top.to_sv
puts sv

# Write the generated SV to build/rtl/top.sv
outDir  = File.join(__dir__, "..", "build", "rtl")
FileUtils.mkdir_p(outDir)
outFile = File.join(outDir, "top.sv")
File.write(outFile, sv + "\n")
warn "Written to #{outFile}"
