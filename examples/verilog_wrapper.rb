# frozen_string_literal: true
# examples/verilog_wrapper.rb
#
# Demonstrates the Verilog-compatible wrapper generator.
#
# Covered syntax:
# - v_wrapper method on ModuleDef
# - packed array ports flattened to flat bit vectors
# - unpacked array ports expanded to individual scalar ports
# - parameter passthrough
#
# Run:
#   xmake rtl -f vwr

$LOAD_PATH.unshift(File.join(__dir__, "..", "lib"))
require "rsv"
include RSV

class InnerModule < ModuleDef
  def build
    clk = input("clk", clock)
    rst = input("rst", reset)
    data_in = input("data_in", arr(4, uint(8)))
    data_out = output("data_out", arr(4, uint(8)))
    mem_in = input("mem_in", mem(2, uint(16)))
    flag = output("flag", uint(1))
    count_r = reg("count_r", uint(16), init: 0)

    flag <= count_r[0]
    data_out <= data_in

    with_clk_and_rst(clk, rst)
    always_ff do
      count_r <= count_r + mem_in[0] + mem_in[1]
    end
  end
end

def rtl_output_path(name)
  File.join(__dir__, "..", "build", "rtl", "#{name}.sv")
end

inner = InnerModule.new("inner_module")
inner.to_sv("-")
inner.to_sv(rtl_output_path("inner_module"))

puts "\n// === Verilog Wrapper ===\n\n"

wrapper = inner.v_wrapper("-", wrapper_name: "inner_module_wrapper")
inner.v_wrapper(rtl_output_path("inner_module_wrapper"))

warn "Written to #{rtl_output_path('inner_module')}"
warn "Written to #{rtl_output_path('inner_module_wrapper')}"
