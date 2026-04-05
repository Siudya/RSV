# frozen_string_literal: true
# examples/curried_params.rb
#
# Demonstrates sv_param and curried parameter application.
#
# Covered syntax:
# - class-level sv_param declarations
# - curried call: ClassName.new("name").(sv_params).(meta_params)
# - SvParamRef used as width in uint()/sint()
# - parameter override at instantiation
# - different meta_params produce different module templates
#
# Run:
#   ruby examples/curried_params.rb

$LOAD_PATH.unshift(File.join(__dir__, "..", "lib"))
require "rsv"
include RSV

class ParamCounter < ModuleDef
  WIDTH = sv_param("WIDTH", 8)

  def build(enable_wrap: true)
    clk = input("clk", clock)
    rst = input("rst", reset)
    out = output("count", uint(WIDTH))
    count_r = reg("count_r", uint(WIDTH), init: 0)
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
    clk = input("clk", clock)
    rst = input("rst", reset)
    count_a = output("count_a", uint(16))
    count_b = output("count_b", uint(32))

    # Instance with WIDTH=16, wrapping enabled
    a = ParamCounter.new("param_counter").(WIDTH: 16).(enable_wrap: true)
    a.clk <= clk
    a.rst <= rst
    count_a <= a.count

    # Instance with WIDTH=32, wrapping disabled (different meta_params → different template)
    b = ParamCounter.new("param_counter").(WIDTH: 32).(enable_wrap: false)
    b.clk <= clk
    b.rst <= rst
    count_b <= b.count
  end
end

def rtl_output_path(name)
  File.join(__dir__, "..", "build", "rtl", "curried_#{name}.sv")
end

top = TopCurried.new("curried_top")
top.to_sv("-")
top.to_sv(rtl_output_path("top"))

# Output submodule definitions
ParamCounter.send(:definition_handle_registry).each do |name, handle|
  handle.definition.to_sv(rtl_output_path(name))
  warn "Written to #{rtl_output_path(name)}"
end
warn "Written to #{rtl_output_path('top')}"
