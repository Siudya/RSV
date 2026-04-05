# frozen_string_literal: true
# examples/pop_count_demo.rb
#
# Demonstrates log2ceil utility and pop_count hardware operation.
#
# Covered features:
# - log2ceil: compile-time bit-width calculation
# - pop_count: population count via for-loop accumulator
# - always_comb with pop_count assignment
#
# Run:
#   xmake rtl -f pop_count_demo

$LOAD_PATH.unshift(File.join(__dir__, "..", "lib"))
require "rsv"
include RSV

class PopCountDemo < ModuleDef
  def build
    vec = input("vec", uint(8))
    cnt = output("cnt", uint(log2ceil(8 + 1)))

    cnt_w = wire("cnt_w", uint(log2ceil(8 + 1)))
    cnt <= cnt_w

    always_comb do
      cnt_w <= pop_count(vec)
    end
  end
end

demo = PopCountDemo.new
output_path = File.join(__dir__, "..", "build", "rtl", "pop_count_demo.sv")

demo.to_sv("-")
demo.to_sv(output_path)
warn "Written to #{output_path}"
