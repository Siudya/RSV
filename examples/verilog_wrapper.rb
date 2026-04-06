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
# - vec(N, bundle) ports expanded per field with unpacked dims
#
# Run:
#   xmake rtl -f verilog_wrapper

$LOAD_PATH.unshift(File.join(__dir__, "..", "lib"))
require "rsv"
include RSV

# A simple pixel bundle
class Pixel < BundleDef
  def build
    input :r, uint(8)
    input :g, uint(8)
    input :b, uint(8)
  end
end

# ── Inner module using plain ports + unpacked arrays ──
class InnerModule < ModuleDef
  def build
    let :clk, input(clock)
    let :rst, input(reset)
    let :data_in, input(vec(4, uint(8)))
    let :data_out, output(vec(4, uint(8)))
    let :mem_in, input(vec(2, uint(16)))
    let :flag, output(uint(1))
    let :count_r, reg(uint(16), init: 0)

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
    let :px_in, input(Pixel.new)
    let :px_out, flip(Pixel.new)
    px_out <= px_in
  end
end

# ── Module with vec(N, Bundle) port ──
class MemBundleModule < ModuleDef
  def build
    let :fifo, input(Pixel.new)
    r = output("red0", uint(8))
    r <= fifo.r
  end
end

# ── Generate all modules + wrappers ──

inner = InnerModule.new("inner_module")
bundle_mod = BundleModule.new("bundle_module")
mem_mod = MemBundleModule.new("mem_bundle_module")

RSV::App.main do |app|
  app.after_export do |opts, tops|
    next unless opts[:out_dir]
    tops.each do |t|
      wrapper_name = "#{t.module_name}_wrapper"
      t.v_wrapper(File.join(opts[:out_dir], "#{wrapper_name}.sv"), wrapper_name: wrapper_name)
    end
  end
  app.build { |_opts| [inner, bundle_mod, mem_mod] }
end
