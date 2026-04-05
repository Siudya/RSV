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

# Bundle with sv_param — width is an SV parameter
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

# Stream interface — directions are from master's perspective.
# mst/slv modports are auto-generated.
class StreamIntf < RSV::InterfaceDef
  def build(payload_t:)
    payload = output("payload", payload_t)
    valid   = output("valid",   bit)
    ready   = input("ready",    bit)
  end
end

# AXI-like interface with meta-param widths
class SimpleBus < RSV::InterfaceDef
  def build(addr_w: 32, data_w: 32)
    addr  = output("addr",   uint(addr_w))
    wdata = output("wdata",  uint(data_w))
    rdata = input("rdata",   uint(data_w))
    wen   = output("wen",    bit)
    ren   = output("ren",    bit)
    ready = input("ready",   bit)
  end
end

# ── Modules Using Bundles & Interfaces ───────────────────────────────────────

# Demonstrates bundle basics, partial reset, nested bundle, mem, and sv_param
class PixelProcessor < RSV::ModuleDef
  def build
    clk = input("clk", clock)
    rst = input("rst", reset)

    px_in  = input("px_in", Pixel.new)
    px_out = output("px_out", Pixel.new)

    # Partial reset — only r is cleared on reset, g and b are NOT reset
    px_reg = reg("px_reg", Pixel.new, init: { "r" => 0 })

    # Full reset — all fields cleared
    px_buf = reg("px_buf", Pixel.new, init: { "r" => 0, "g" => 0, "b" => 0 })

    # Wire with nested bundle
    hdr = wire("hdr", FrameHeader.new)

    # Bundle array (mem of structs)
    fifo = wire("fifo", mem(4, Pixel.new))

    # Parameterized bundle: W=8 (default) vs W=16 — produces two typedefs
    pkt8  = wire("pkt8",  DataPacket.new)
    pkt16 = wire("pkt16", DataPacket.new.(W: 16))

    with_clk_and_rst(clk, rst)

    px_out <= px_buf

    always_ff do
      # Field access on reg
      px_reg.r <= px_in.r
      # Field access through mem index
      px_buf.r <= fifo[0].r
      px_buf.g <= fifo[0].g
      px_buf.b <= fifo[0].b
    end
  end
end

# Parameterized interface — payload type is passed as a meta parameter
class StreamSink < RSV::ModuleDef
  def build
    clk = input("clk", clock)
    rst = input("rst", reset)
    # StreamIntf parameterized with Pixel bundle as payload — .slv for slave modport
    stream = intf("stream", StreamIntf.new(payload_t: Pixel.new).slv)
    pix = output("pixel_out", Pixel.new)
    rdy = output("ready_out", bit)

    pix <= stream.payload
    rdy <= stream.ready
  end
end

# Meta-param interface — addr/data widths set at elaboration time
class BusSlave < RSV::ModuleDef
  def build
    clk  = input("clk", clock)
    rst  = input("rst", reset)
    bus  = intf("bus", SimpleBus.new(addr_w: 16, data_w: 32).slv)
    data = output("reg_data", uint(32))

    data <= bus.rdata
  end
end

# ── Interface Interconnect ───────────────────────────────────────────────────

# Whole-interface interconnect: mst <= slv expands to per-field assign
class StreamBridge < RSV::ModuleDef
  def build
    m = intf("m_stream", StreamIntf.new(payload_t: Pixel.new))
    s = intf("s_stream", StreamIntf.new(payload_t: Pixel.new).slv)
    m <= s
  end
end

# Individual field assignment on interface ports
class StreamAdapter < RSV::ModuleDef
  def build
    clk = input("clk", clock)
    rst = input("rst", reset)
    s = intf("stream", StreamIntf.new(payload_t: Pixel.new).slv)
    px_out   = output("px_out",   Pixel.new)
    v_out    = output("v_out",    bit)
    rdy_in   = input("rdy_in",   bit)

    px_out <= s.payload
    v_out  <= s.valid
    s.ready <= rdy_in
  end
end

# Module-level sv_param + bundle with meta-param selected width
class PacketRouter < RSV::ModuleDef
  PKT_W = sv_param "PKT_W", 8
  def build(pkt_w: 8)
    clk = input("clk", clock)
    rst = input("rst", reset)

    # Bundle width matches the meta-param (concrete at elaboration time)
    pkt_t = DataPacket.new.(W: pkt_w)
    pkt_in  = input("pkt_in",  pkt_t)
    pkt_out = output("pkt_out", pkt_t)

    # Partial reset — only valid bit is cleared; data retains previous value
    pkt_r = reg("pkt_r", pkt_t, init: { "valid" => 0 })

    with_clk_and_rst(clk, rst)

    pkt_out <= pkt_r

    always_ff do
      pkt_r.valid <= pkt_in.valid
      pkt_r.data  <= pkt_in.data
    end
  end
end

# ── Template-style: bundle type as module parameter ──────────────────────────

# Generic pipeline register — bundle type is passed as meta parameter
class PipeReg < RSV::ModuleDef
  def build(dat_t:, init_fields: {})
    clk = input("clk", clock)
    rst = input("rst", reset)
    d_in  = input("d_in", dat_t)
    d_out = output("d_out", dat_t)
    d_r = reg("d_r", dat_t, init: init_fields.empty? ? nil : init_fields)
    with_clk_and_rst(clk, rst)
    d_out <= d_r
    always_ff { d_r <= d_in }
  end
end

# ── Generate Output ──────────────────────────────────────────────────────────
outdir = File.join(__dir__, "..", "build", "rtl")
FileUtils.mkdir_p(outdir)

# Emit interface files
stream_intf = StreamIntf.new(payload_t: Pixel.new)
stream_def = stream_intf.instance_variable_get(:@_intf_def)
File.write(File.join(outdir, "stream_intf.sv"), stream_def.to_sv)

bus_intf = SimpleBus.new(addr_w: 16, data_w: 32)
bus_def = bus_intf.instance_variable_get(:@_intf_def)
File.write(File.join(outdir, "simple_bus.sv"), bus_def.to_sv)

# Emit modules
[PixelProcessor, StreamSink, BusSlave, StreamBridge, StreamAdapter].each do |klass|
  mod = klass.new
  name = mod.module_name.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
  File.write(File.join(outdir, "#{name}.sv"), mod.to_sv)
end

# PacketRouter with meta-param pkt_w=32 → uses data_packet_t with W=32
router = PacketRouter.new("PacketRouter").(PKT_W: 32).(pkt_w: 32)
File.write(File.join(outdir, "packet_router.sv"), router.to_sv)

# Template module instantiated with different bundle types
pipe_px = PipeReg.new(dat_t: Pixel.new, init_fields: { "r" => 0 })
File.write(File.join(outdir, "pipe_reg_pixel.sv"), pipe_px.to_sv)

pipe_pkt = PipeReg.new(dat_t: DataPacket.new.(W: 32), init_fields: { "valid" => 0 })
File.write(File.join(outdir, "pipe_reg_pkt.sv"), pipe_pkt.to_sv)

puts "Generated:"
Dir.glob(File.join(outdir, "*.sv")).sort.each { |f| puts "  #{f}" }
