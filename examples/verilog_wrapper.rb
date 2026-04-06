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
# - bundle ports flattened to individual signal ports
# - mem(N, bundle) ports expanded per field with unpacked dims
#
# Run:
#   xmake rtl -f verilog_wrapper

$LOAD_PATH.unshift(File.join(__dir__, "..", "lib"))
require "rsv"
include RSV

# A simple pixel bundle
class Pixel < BundleDef
  def build
    input("r", uint(8))
    input("g", uint(8))
    input("b", uint(8))
  end
end

# ── Inner module using plain ports + packed/unpacked arrays ──
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

# ── Module with bundle ports ──
class BundleModule < ModuleDef
  def build
    px_in = iodecl("px_in", Pixel.new)
    px_out = iodecl("px_out", flip(Pixel.new))
    px_out <= px_in
  end
end

# ── Module with mem(N, Bundle) port ──
class MemBundleModule < ModuleDef
  def build
    fifo = iodecl("fifo", Pixel.new)
    r = output("red0", uint(8))
    r <= fifo.r
  end
end

def rtl_output_path(name)
  File.join(__dir__, "..", "build", "rtl", "#{name}.sv")
end

# ── Generate all wrappers ──

# 1. Plain + packed/unpacked
inner = InnerModule.new("inner_module")
inner.to_sv(rtl_output_path("inner_module"))
inner.v_wrapper(rtl_output_path("inner_module_wrapper"), wrapper_name: "inner_module_wrapper")

# 2. Bundle port
bundle_mod = BundleModule.new("bundle_module")
bundle_mod.to_sv(rtl_output_path("bundle_module"))
bundle_mod.v_wrapper(rtl_output_path("bundle_module_wrapper"), wrapper_name: "bundle_module_wrapper")

# 3. mem(N, Bundle) port
mem_mod = MemBundleModule.new("mem_bundle_module")
mem_mod.to_sv(rtl_output_path("mem_bundle_module"))
mem_mod.v_wrapper(rtl_output_path("mem_bundle_module_wrapper"), wrapper_name: "mem_bundle_module_wrapper")

# Print summary to stdout
puts "// Generated SV wrappers demonstrating:"
puts "//   1. inner_module_wrapper       — packed arr + unpacked mem"
puts "//   2. bundle_module_wrapper      — bundle (flat) ports"
puts "//   3. mem_bundle_module_wrapper  — mem(2, Pixel) ports"
puts ""

# Print one wrapper as demonstration
$stderr.puts mem_mod.v_wrapper(wrapper_name: "mem_bundle_module_wrapper")
