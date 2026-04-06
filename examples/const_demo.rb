# frozen_string_literal: true
# examples/const_demo.rb
#
# Demonstrates the const (localparam) feature.
#
# Covered syntax:
# - const declarations for localparam
# - using const values in expressions
#
# Run:
#   xmake rtl -f cst

$LOAD_PATH.unshift(File.join(__dir__, "..", "lib"))
require "rsv"

class ConstDemo < RSV::ModuleDef
  def build
    clk = input("clk", bit)
    rst = input("rst", bit)
    out = output("out", uint(16))

    magic  = const("MAGIC", uint(16, 0xBEEF))
    offset = const("OFFSET", sint(8, -3))

    count_r = reg("count_r", uint(16), init: 0)
    with_clk_and_rst(clk, rst)
    always_ff do
      svif(1) do
        count_r <= count_r + 1
      end
    end

    out <= count_r + magic
  end
end

mod = ConstDemo.new

RSV::App.main(mod)
