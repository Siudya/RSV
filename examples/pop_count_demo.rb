# frozen_string_literal: true
# examples/pop_count_demo.rb
#
# Demonstrates log2ceil utility and pop_count hardware operation.
#
# Covered features:
# - log2ceil: compile-time bit-width calculation
# - pop_count: population count via for-loop accumulator
# - pop_count auto-wire expansion (no manual wire declaration)
# - pop_count in always_comb, always_ff, and module level
#
# Run:
#   xmake rtl -f pop_count_demo

$LOAD_PATH.unshift(File.join(__dir__, "..", "lib"))
require "rsv"
include RSV

class PopCountDemo < ModuleDef
  def build
    clk = input("clk", clock)
    rst = input("rst", reset)
    vec = input("vec", uint(8))
    cnt = output("cnt", uint(log2ceil(8 + 1)))
    cnt_reg = output("cnt_reg", uint(log2ceil(8 + 1)))

    # module-level: auto creates vec_pop_count wire + always_comb
    cnt <= pop_count(vec)

    # registered: auto-wire in always_ff, latched on clock edge
    cnt_r = reg("cnt_r", uint(log2ceil(8 + 1)), init: 0)
    cnt_reg <= cnt_r

    with_clk_and_rst(clk, rst)
    always_ff do
      cnt_r <= pop_count(vec)
    end
  end
end

demo = PopCountDemo.new

RSV::App.main(demo)
