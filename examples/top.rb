# frozen_string_literal: true
# examples/top.rb
#
# Demonstrates module instantiation by creating a top-level wrapper that
# instantiates two Counter modules with different widths.
# Run:  ruby examples/top.rb

$LOAD_PATH.unshift(File.join(__dir__, "..", "lib"))
require "rsv"

top = RSV::ModuleDef.new("Top") do
  input  "clk"
  input  "rst_n"
  input  "en_a"
  input  "en_b"
  output "count_a", width: 8
  output "count_b", width: 16

  instantiate "Counter", "u_counter_a",
    params:      { "WIDTH" => 8 },
    connections: {
      "clk"   => "clk",
      "rst_n" => "rst_n",
      "en"    => "en_a",
      "count" => "count_a"
    }

  instantiate "Counter", "u_counter_b",
    params:      { "WIDTH" => 16 },
    connections: {
      "clk"   => "clk",
      "rst_n" => "rst_n",
      "en"    => "en_b",
      "count" => "count_b"
    }
end

sv = top.toSv
puts sv

outDir  = File.join(__dir__, "..", "out")
Dir.mkdir(outDir) unless Dir.exist?(outDir)
outFile = File.join(outDir, "top.sv")
File.write(outFile, sv + "\n")
warn "Written to #{outFile}"
