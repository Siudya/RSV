$LOAD_PATH.unshift(File.join(__dir__, "..", "lib"))
require "rsv"
require "fileutils"

# ── Bundle Definitions ──────────────────────────────────────────────

# Simple bundle
class Pixel < RSV::BundleDef
  def build
    r = field("r", uint(8))
    g = field("g", uint(8))
    b = field("b", uint(8))
  end
end

# Bundle with meta_param — width is a Ruby argument
class DataPacket < RSV::BundleDef
  def build(w: 8)
    valid = field("valid", bit)
    data  = field("data",  uint(w))
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

# ── Modules Using Bundles ───────────────────────────────────────────

# Demonstrates bundle basics, partial reset, nested bundle, mem, and meta_param
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

    # Parameterized bundle: w=8 (default) vs w=16
    pkt8  = wire("pkt8",  DataPacket.new(w: 8))
    pkt16 = wire("pkt16", DataPacket.new(w: 16))

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

# Module with meta_param for packet width
class PacketRouter < RSV::ModuleDef
  def build(pkt_w: 8)
    clk = input("clk", clock)
    rst = input("rst", reset)

    # Bundle width matches the meta-param (concrete at elaboration time)
    pkt_t = DataPacket.new(w: pkt_w)
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

# Emit modules
[PixelProcessor].each do |klass|
  mod = klass.new
  name = mod.module_name.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
  File.write(File.join(outdir, "#{name}.sv"), mod.to_sv)
end

# PacketRouter with meta-param pkt_w=32
router = PacketRouter.new("PacketRouter", pkt_w: 32)
File.write(File.join(outdir, "packet_router.sv"), router.to_sv)

# Template module instantiated with different bundle types
pipe_px = PipeReg.new(dat_t: Pixel.new, init_fields: { "r" => 0 })
File.write(File.join(outdir, "pipe_reg_pixel.sv"), pipe_px.to_sv)

pipe_pkt = PipeReg.new(dat_t: DataPacket.new(w: 32), init_fields: { "valid" => 0 })
File.write(File.join(outdir, "pipe_reg_pkt.sv"), pipe_pkt.to_sv)

puts "Generated:"
Dir.glob(File.join(outdir, "*.sv")).sort.each { |f| puts "  #{f}" }
