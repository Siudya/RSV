# frozen_string_literal: true
# examples/type_conv_demo.rb
#
# Demonstrates the `.as_type(target)` conversion API for reshaping signals
# between different data types.
#
# Covered features:
# - scalar → scalar: truncation (keep LSBs) and zero-extension (pad MSBs)
# - uint → sint: signed reinterpretation
# - bundle → uint: flatten bundle fields into a packed uint
# - uint → bundle: reshape uint into bundle fields via bit slicing
# - uint → mem: reshape uint into memory elements
# - mem → uint: flatten memory elements into a packed uint
# - bundle → bundle: cross-bundle conversion (flatten + reshape)
# - uint → mem(bundle): reshape uint into memory of bundles
#
# Run:
#   xmake rtl -f type_conv

$LOAD_PATH.unshift(File.join(__dir__, "..", "lib"))
require "rsv"
include RSV

class Pixel < BundleDef
  def build
    input :r, uint(8)
    input :g, uint(8)
    input :b, uint(8)
  end
end

class Coord < BundleDef
  def build
    input :x, uint(12)
    input :y, uint(12)
  end
end

class TypeConvDemo < ModuleDef
  def build
    let :wide, input(uint(32))
    let :narrow, input(uint(8))
    let :pixel_in, input(uint(24))
    let :mem_in, input(uint(32))
    let :bundle_flat_in, input(Pixel.new)
    let :mem_bndl_in, input(uint(48))

    # ── scalar → scalar ─────────────────────────────────────────────
    # truncation: 32-bit → 8-bit, keeps LSBs
    let :trunc_out, output(uint(8))
    trunc_out <= wide.as_type(uint(8))

    # zero-extension: 8-bit → 32-bit, pads MSBs with zeros
    let :ext_out, output(uint(32))
    ext_out <= narrow.as_type(uint(32))

    # ── uint → sint ─────────────────────────────────────────────────
    let :signed_out, output(sint(8))
    signed_out <= narrow.as_type(sint(8))

    # ── uint → bundle ───────────────────────────────────────────────
    # Reshape 24-bit uint into Pixel bundle: r[23:16], g[15:8], b[7:0]
    pxl = pixel_in.as_type(Pixel.new)
    let :pxl_r, output(uint(8))
    let :pxl_g, output(uint(8))
    let :pxl_b, output(uint(8))
    pxl_r <= pxl.r
    pxl_g <= pxl.g
    pxl_b <= pxl.b

    # ── bundle → uint ───────────────────────────────────────────────
    # Flatten Pixel bundle into a packed 24-bit uint
    let :pxl_flat, output(uint(24))
    pxl_flat <= bundle_flat_in.as_type(uint(24))

    # ── uint → mem ──────────────────────────────────────────────────
    # Reshape 32-bit uint into mem(4, uint(8)): elem[0] = [7:0], ..., elem[3] = [31:24]
    m = mem_in.as_type(mem(4, uint(8)))
    let :mem_elem0, output(uint(8))
    let :mem_elem2, output(uint(8))
    mem_elem0 <= m[0]
    mem_elem2 <= m[2]

    # ── bundle → bundle (cross-type) ────────────────────────────────
    # Convert Pixel (24-bit) → Coord (24-bit): flatten + reshape
    coord = bundle_flat_in.as_type(Coord.new)
    let :coord_x, output(uint(12))
    let :coord_y, output(uint(12))
    coord_x <= coord.x
    coord_y <= coord.y

    # ── uint → mem(bundle) ──────────────────────────────────────────
    # Reshape 48-bit uint into mem(2, Pixel): each element is a 24-bit Pixel
    mb = mem_bndl_in.as_type(mem(2, Pixel.new))
    let :mb_0_r, output(uint(8))
    let :mb_1_g, output(uint(8))
    mb_0_r <= mb[0].r
    mb_1_g <= mb[1].g
  end
end

demo = TypeConvDemo.new

RSV::App.main(demo)
