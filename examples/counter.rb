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
    let :clk, input(bit)
    let :rst, input(bit)
    let :en, input(bit)
    let :count, output(uint(width))

    let :count_r, reg(uint(width), init: 0)
    let :count_next, expr(count_r + 1)

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

RSV::App.main(Counter.new(width: 8))
