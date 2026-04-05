$LOAD_PATH.unshift(File.join(__dir__, "..", "lib"))
require "rsv"
require "fileutils"

# ── Bundle (Struct) Definitions ──────────────────────────────────────────────

# Simple bundle
class Pixel < RSV::BundleDef
  def build
    r = field("r", uint(8))
    g = field("g", uint(8))
    b = field("b", uint(8))
  end
end

# Bundle with sv_param
class DataPacket < RSV::BundleDef
  W = sv_param "W", 8
  def build
    valid = field("valid", bit)
    data  = field("data",  uint(W))
  end
end

# Nested bundle
class FrameHeader < RSV::BundleDef
  def build
    pixel = field("pixel",  Pixel.new)
    x_pos = field("x_pos",  uint(12))
    y_pos = field("y_pos",  uint(12))
    last  = field("last",   bit)
  end
end

# ── Interface Definitions ────────────────────────────────────────────────────

# Stream interface with struct payload
class StreamIntf < RSV::InterfaceDef
  def build
    payload = field("payload", Pixel.new)
    valid   = field("valid",   bit)
    ready   = field("ready",   bit)
    modport "src",  inputs: [ready], outputs: [payload, valid]
    modport "sink", inputs: [payload, valid], outputs: [ready]
  end
end

# AXI-like interface with parametric width
class SimpleBus < RSV::InterfaceDef
  def build(addr_w: 32, data_w: 32)
    addr  = field("addr",   uint(addr_w))
    wdata = field("wdata",  uint(data_w))
    rdata = field("rdata",  uint(data_w))
    wen   = field("wen",    bit)
    ren   = field("ren",    bit)
    ready = field("ready",  bit)
    modport "master", inputs: [rdata, ready], outputs: [addr, wdata, wen, ren]
    modport "slave",  inputs: [addr, wdata, wen, ren], outputs: [rdata, ready]
  end
end

# ── Modules Using Bundles & Interfaces ───────────────────────────────────────

# Module using simple bundle, nested bundle, and partial reset
class PixelProcessor < RSV::ModuleDef
  def build
    clk = input("clk", clock)
    rst = input("rst", reset)

    px_in  = input("px_in", Pixel.new)
    px_out = output("px_out", Pixel.new)

    # Register with partial reset (only r field)
    px_reg = reg("px_reg", Pixel.new, init: { "r" => 0, "g" => 0, "b" => 0 })

    # Wire with nested bundle
    hdr = wire("hdr", FrameHeader.new)

    # Bundle array (mem)
    fifo = wire("fifo", mem(4, Pixel.new))

    # Parameterized bundle
    pkt8  = wire("pkt8", DataPacket.new)
    pkt16 = wire("pkt16", DataPacket.new.(W: 16))

    with_clk_and_rst(clk, rst)

    # Assign via field access
    px_out <= px_reg

    always_ff do
      px_reg.r <= px_in.r
      px_reg.g <= px_in.g
      px_reg.b <= fifo[0].b
    end
  end
end

# Module using interface port
class StreamSink < RSV::ModuleDef
  def build
    clk = input("clk", clock)
    rst = input("rst", reset)
    stream = interface_port("stream", StreamIntf.new, modport: "sink")
    pix = output("pixel_out", Pixel.new)
    rdy = output("ready_out", bit)

    pix <= stream.payload
    rdy <= stream.ready
  end
end

# Module using bus interface
class BusSlave < RSV::ModuleDef
  def build
    clk  = input("clk", clock)
    rst  = input("rst", reset)
    bus  = interface_port("bus", SimpleBus.new(addr_w: 16, data_w: 32), modport: "slave")
    data = output("reg_data", uint(32))

    data <= bus.rdata
  end
end

# ── Generate Output ──────────────────────────────────────────────────────────
outdir = File.join(__dir__, "..", "build", "rtl")
FileUtils.mkdir_p(outdir)

# Emit interface files
stream_intf = StreamIntf.new
stream_def = stream_intf.instance_variable_get(:@_intf_def)
File.write(File.join(outdir, "stream_intf.sv"), stream_def.to_sv)

bus_intf = SimpleBus.new(addr_w: 16, data_w: 32)
bus_def = bus_intf.instance_variable_get(:@_intf_def)
File.write(File.join(outdir, "simple_bus.sv"), bus_def.to_sv)

# Emit modules
proc_mod = PixelProcessor.new
File.write(File.join(outdir, "pixel_processor.sv"), proc_mod.to_sv)

sink_mod = StreamSink.new
File.write(File.join(outdir, "stream_sink.sv"), sink_mod.to_sv)

slave_mod = BusSlave.new
File.write(File.join(outdir, "bus_slave.sv"), slave_mod.to_sv)

puts "Generated:"
Dir.glob(File.join(outdir, "*.sv")).sort.each { |f| puts "  #{f}" }
