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
# - interface ports expanded to flat Verilog ports
# - bundle (struct) ports expanded to flat Verilog ports
# - mem(N, bundle) ports expanded per element and per field
# - interface with bundle-typed fields
#
# Run:
#   xmake rtl -f verilog_wrapper

$LOAD_PATH.unshift(File.join(__dir__, "..", "lib"))
require "rsv"
include RSV

# A simple pixel bundle (struct packed)
class Pixel < BundleDef
  def build
    field("r", uint(8))
    field("g", uint(8))
    field("b", uint(8))
  end
end

# A simple bus interface with handshake
class SimpleBus < InterfaceDef
  def build
    output("addr", uint(16))
    output("wdata", uint(32))
    input("rdata", uint(32))
    output("valid", bit)
    input("ready", bit)
  end
end

# A stream interface carrying a pixel payload
class PixelStream < InterfaceDef
  def build
    output("payload", Pixel.new)
    output("valid", bit)
    input("ready", bit)
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

# ── Module with interface ports ──
class IntfModule < ModuleDef
  def build
    clk = input("clk", clock)
    rst = input("rst", reset)
    bus = intf("bus", SimpleBus.new.slv)
    o = output("out", uint(32))
    o <= bus.rdata
  end
end

# ── Module with bundle (struct) ports ──
class BundleModule < ModuleDef
  def build
    px_in = input("px_in", Pixel.new)
    px_out = output("px_out", Pixel.new)
    px_out <= px_in
  end
end

# ── Module with mem(N, Bundle) port ──
class MemBundleModule < ModuleDef
  def build
    fifo = input("fifo", mem(2, Pixel.new))
    r = output("red0", uint(8))
    r <= fifo[0].r
  end
end

# ── Module with interface containing bundle field ──
class StreamModule < ModuleDef
  def build
    clk = input("clk", clock)
    rst = input("rst", reset)
    s = intf("s", PixelStream.new.slv)
    v = output("valid_out", bit)
    v <= s.valid
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

# 2. Interface port
intf_mod = IntfModule.new("intf_module")
intf_mod.to_sv(rtl_output_path("intf_module"))
intf_mod.v_wrapper(rtl_output_path("intf_module_wrapper"), wrapper_name: "intf_module_wrapper")

# 3. Bundle port
bundle_mod = BundleModule.new("bundle_module")
bundle_mod.to_sv(rtl_output_path("bundle_module"))
bundle_mod.v_wrapper(rtl_output_path("bundle_module_wrapper"), wrapper_name: "bundle_module_wrapper")

# 4. mem(N, Bundle) port
mem_mod = MemBundleModule.new("mem_bundle_module")
mem_mod.to_sv(rtl_output_path("mem_bundle_module"))
mem_mod.v_wrapper(rtl_output_path("mem_bundle_module_wrapper"), wrapper_name: "mem_bundle_module_wrapper")

# 5. Interface with bundle field
stream_mod = StreamModule.new("stream_module")
stream_mod.to_sv(rtl_output_path("stream_module"))
stream_mod.v_wrapper(rtl_output_path("stream_module_wrapper"), wrapper_name: "stream_module_wrapper")

# Print summary to stdout
puts "// Generated SV wrappers demonstrating:"
puts "//   1. inner_module_wrapper   — packed arr + unpacked mem"
puts "//   2. intf_module_wrapper    — interface port (slv modport)"
puts "//   3. bundle_module_wrapper  — struct (bundle) port"
puts "//   4. mem_bundle_module_wrapper — mem(2, Pixel) port"
puts "//   5. stream_module_wrapper  — interface with bundle payload"
puts ""

# Print one wrapper as demonstration
$stderr.puts stream_mod.v_wrapper(wrapper_name: "stream_module_wrapper")
