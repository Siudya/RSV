# frozen_string_literal: true
# examples/curried_params.rb
#
# Demonstrates meta_param usage for parameterized modules.
#
# Covered syntax:
# - meta_param as build() keyword arguments
# - different meta_params produce different module templates
# - Ruby-level parameterization (width baked into SV output)
#
# Run:
#   xmake rtl -f cur

$LOAD_PATH.unshift(File.join(__dir__, "..", "lib"))
require "rsv"
include RSV

class ParamCounter < ModuleDef
  def build(width: 8, enable_wrap: true)
    let :clk, input(clock)
    let :rst, input(reset)
    out = output("count", uint(width))
    let :count_r, reg(uint(width), init: 0)
    out <= count_r

    with_clk_and_rst(clk, rst)
    always_ff do
      if enable_wrap
        svif(count_r.and_r) do
          count_r <= 0
        end
        svelse do
          count_r <= count_r + 1
        end
      else
        count_r <= count_r + 1
      end
    end
  end
end

class TopCurried < ModuleDef
  def build
    let :clk, input(clock)
    let :rst, input(reset)
    let :count_a, output(uint(16))
    let :count_b, output(uint(32))

    # Instance with width=16, wrapping enabled
    a = ParamCounter.new("param_counter", width: 16, enable_wrap: true)
    a.clk <= clk
    a.rst <= rst
    count_a <= a.count

    # Instance with width=32, wrapping disabled (different meta_params → different template)
    b = ParamCounter.new("param_counter", width: 32, enable_wrap: false)
    b.clk <= clk
    b.rst <= rst
    count_b <= b.count
  end
end

top = TopCurried.new("curried_top")

RSV::App.main(top)
