# frozen_string_literal: true
# examples/counter.rb
#
# Generates a parameterized synchronous counter with active-low reset.
# Run:  ruby examples/counter.rb

$LOAD_PATH.unshift(File.join(__dir__, "..", "lib"))
require "rsv"

counter = RSV::ModuleDef.new("Counter") do
  parameter "WIDTH", 8

  input  "clk"
  input  "rst_n"
  input  "en"
  output "count", width: "WIDTH"

  logic "count_r", width: "WIDTH"

  assignStmt "count", "count_r"

  alwaysFf "posedge clk or negedge rst_n" do
    ifStmt "!rst_n" do
      nbAssign "count_r", "'0"
    end
    elsifStmt "en" do
      nbAssign "count_r", "count_r + 1'b1"
    end
  end
end

sv = counter.toSv
puts sv

# Write the generated SV to out/counter.sv
outDir  = File.join(__dir__, "..", "out")
Dir.mkdir(outDir) unless Dir.exist?(outDir)
outFile = File.join(outDir, "counter.sv")
File.write(outFile, sv + "\n")
warn "Written to #{outFile}"
