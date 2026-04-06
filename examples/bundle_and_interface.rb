$LOAD_PATH.unshift(File.join(__dir__, "..", "lib"))
require "rsv"

# ── Bundle Definitions ──────────────────────────────────────────────

# Simple bundle
class Pixel < RSV::BundleDef
  def build
    input :r, uint(8)
    input :g, uint(8)
    input :b, uint(8)
  end
end

# Bundle with meta_param — width is a Ruby argument
class DataPacket < RSV::BundleDef
  def build(w: 8)
    input :valid, bit
    input :data,  uint(w)
  end
end

# Nested bundle
class FrameHeader < RSV::BundleDef
  def build
    input :pixel,  Pixel.new
    input :x_pos,  uint(12)
    input :y_pos,  uint(12)
    input :last,   bit
  end
end

# ── Modules Using Bundles ───────────────────────────────────────────

# Demonstrates bundle basics, partial reset, nested bundle, mem, and meta_param
class PixelProcessor < RSV::ModuleDef
  def build
    let :clk, input(clock)
    let :rst, input(reset)

    let :px_in, input(Pixel.new)
    let :px_out, flip(Pixel.new)

    # Partial reset — only r is cleared on reset, g and b are NOT reset
    let :px_reg, reg(Pixel.new, init: { "r" => 0 })

    # Full reset — all fields cleared
    let :px_buf, reg(Pixel.new, init: { "r" => 0, "g" => 0, "b" => 0 })

    # Wire with nested bundle
    let :hdr, wire(FrameHeader.new)

    # Bundle array (mem of structs)
    let :fifo, wire(mem(4, Pixel.new))

    # Parameterized bundle: w=8 (default) vs w=16
    let :pkt8,  wire(DataPacket.new(w: 8))
    let :pkt16, wire(DataPacket.new(w: 16))

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
    let :clk, input(clock)
    let :rst, input(reset)

    # Bundle width matches the meta-param (concrete at elaboration time)
    pkt_t = DataPacket.new(w: pkt_w)
    let :pkt_in,  input(pkt_t)
    let :pkt_out, flip(pkt_t)

    # Partial reset — only valid bit is cleared; data retains previous value
    let :pkt_r, reg(pkt_t, init: { "valid" => 0 })

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
    let :clk, input(clock)
    let :rst, input(reset)
    let :d_in, input(dat_t)
    let :d_out, flip(dat_t)
    let :d_r, reg(dat_t, init: init_fields.empty? ? nil : init_fields)
    with_clk_and_rst(clk, rst)
    d_out <= d_r
    always_ff { d_r <= d_in }
  end
end

# ── Generate Output ──────────────────────────────────────────────────────────

# Emit all top-level modules
pixel_proc = PixelProcessor.new
router = PacketRouter.new("PacketRouter", pkt_w: 32)
pipe_px = PipeReg.new(dat_t: Pixel.new, init_fields: { "r" => 0 })
pipe_pkt = PipeReg.new(dat_t: DataPacket.new(w: 32), init_fields: { "valid" => 0 })

RSV::App.main([pixel_proc, router, pipe_px, pipe_pkt])
