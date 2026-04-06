# frozen_string_literal: true
# examples/import_demo.rb
#
# Demonstrates `RSV.import_sv` by importing a small SystemVerilog module that
# lives alongside the example scripts and instantiating it as a black box.
#
# Covered syntax:
# - `RSV.import_sv`
# - imported parameter overrides
# - imported module instantiation
# - connecting imported ports with both assignment directions
#
# Run:
#   xmake rtl -f imp

$LOAD_PATH.unshift(File.join(__dir__, "..", "lib"))
require "rsv"

ImportedCounter = RSV.import_sv(
  File.join(__dir__, "imported_counter.sv"),
  top: "ImportedCounter",
  incdirs: [__dir__]
)

class ImportDemo < RSV::ModuleDef
  def build
    clk = input("clk", bit)
    rst_n = input("rst_n", bit)
    din = input("din", uint(12))
    dout = output("dout", uint(12))
    mem_tap = output("mem_tap", mem([4], uint(8)))

    counter = ImportedCounter.new(inst_name: "u_imported_counter", WIDTH: 12)
    counter.clk <= clk
    rst_n >= counter.rst_n
    din >= counter.din
    dout <= counter.dout
    mem_tap <= counter.mem
  end
end

import_demo = ImportDemo.new

RSV::App.main(import_demo)
