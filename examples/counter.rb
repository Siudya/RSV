# frozen_string_literal: true
# examples/counter.rb
#
# Generates a synchronous counter with meta-parameter width.
#
# Covered syntax:
# - meta_param (build keyword arguments)
# - input/output ports
# - uint data types
# - expr(...) inferred wires
# - reg(...) with reset init
# - with_clk_and_rst + always_ff + svif
# - continuous assignment with <=
#
# Run:
#   xmake rtl -f ctr

$LOAD_PATH.unshift(File.join(__dir__, "..", "lib"))
require "rsv"

class Counter < RSV::ModuleDef
  def build(width: 8)
    clk = input("clk", bit)
    rst = input("rst", bit)
    en = input("en", bit)
    count = output("count", uint(width))

    count_r = reg("count_r", uint(width), init: 0)
    count_next = expr("count_next", count_r + 1)

    count <= count_r

    # Use the implicit clock/reset domain so the block reads like ordinary RTL.
    with_clk_and_rst(clk, rst)
    always_ff do
      svif(en) do
        count_r <= count_next
      end
    end
  end
end

counter = Counter.new(width: 8)
output_path = File.join(__dir__, "..", "build", "rtl", "counter.sv")

counter.to_sv("-")
counter.to_sv(output_path)
warn "Written to #{output_path}"
