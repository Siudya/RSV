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

  assign_stmt "count", "count_r"

  always_ff "posedge clk or negedge rst_n" do
    if_stmt "!rst_n" do
      nb_assign "count_r", "'0"
    end
    elsif_stmt "en" do
      nb_assign "count_r", "count_r + 1'b1"
    end
  end
end

sv = counter.to_sv
puts sv

# Write the generated SV to out/counter.sv
out_dir  = File.join(__dir__, "..", "out")
Dir.mkdir(out_dir) unless Dir.exist?(out_dir)
out_file = File.join(out_dir, "counter.sv")
File.write(out_file, sv + "\n")
warn "Written to #{out_file}"
