# frozen_string_literal: true
# examples/top.rb
#
# Demonstrates module instantiation by creating a top-level wrapper that
# instantiates two Counter modules with different widths.
#
# Covered syntax:
# - class-based submodule instantiation
# - deterministic `inst_name:`
# - left and right assignment forms for instance connections
# - reusing a parameterized ModuleDef
#
# Run:
#   ruby examples/top.rb

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
    count_next = expr("count_next", count_r + 1)

    count <= count_r

    with_clk_and_rst(clk, rst)
    always_ff do
      svif(en) do
        count_r <= count_next
      end
    end
  end
end

class Top < RSV::ModuleDef
  def build
    clk = input("clk", bit)
    rst = input("rst", bit)
    en_a = input("en_a", bit)
    en_b = input("en_b", bit)
    count_a = output("count_a", uint(8))
    count_b = output("count_b", uint(16))

    # Show the left-assignment connection style.
    counter_a = Counter.new(inst_name: "u_counter_a", width: 8)
    counter_a.clk <= clk
    counter_a.rst <= rst
    counter_a.en <= en_a
    count_a <= counter_a.count

    # Show the equivalent right-assignment connection style.
    counter_b = Counter.new(inst_name: "u_counter_b", width: 16)
    clk >= counter_b.clk
    rst >= counter_b.rst
    en_b >= counter_b.en
    counter_b.count >= count_b
  end
end

top = Top.new
output_path = File.join(__dir__, "..", "build", "rtl", "top.sv")

top.to_sv("-")
top.to_sv(output_path)
warn "Written to #{output_path}"
