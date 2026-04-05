# frozen_string_literal: true
# examples/storage_streams.rb
#
# Demonstrates shaped storage declarations and the stream-view API across scalar,
# packed, unpacked, and mixed shapes.
#
# Covered syntax:
# - `arr(...)`, `mem(...)`, nested mixed shapes, and fill helpers
# - indexing packed arrays, memories, and mixed shapes
# - `sv_take`, `sv_select`, `sv_foreach`, `sv_reduce`, `sv_map`
# - nested stream traversal over mixed / multi-dimensional shapes
# - explicit `always_ff(clock, reset)` with negedge clock and active-low reset
#
# Run:
#   xmake rtl -f str

$LOAD_PATH.unshift(File.join(__dir__, "..", "lib"))
require "rsv"

class StorageStreams < RSV::ModuleDef
  def build
    clk = input("clk", clock)
    rst_n = input("rst_n", reset)
    update = input("update", bit)
    idx = input("idx", uint(2))
    mask_old = input("mask_old", uint(16))

    packed_word = output("packed_word", uint(8))
    memory_word = output("memory_word", uint(8))
    mixed_word = output("mixed_word", uint(8))
    parity = output("parity", bit)
    selected_bits = output("selected_bits", uint(4))
    packed_slice = output("packed_slice", arr([2], uint(8)))
    mem_slice = output("mem_slice", arr([2], uint(8)))
    mixed_slice = output("mixed_slice", arr([2, 2], uint(8)))

    # Show all three storage styles: packed arrays, unpacked memories, and a
    # mixed "memory of packed arrays". The init helpers produce reset values for
    # the auto-generated reset branch.
    mask_r = reg("mask_r", uint(16), init: 0)
    packed_r = reg("packed_r", arr([4], uint(8)), init: arr.fill(4, uint(8, 0x11)))
    memory_r = reg("memory_r", mem([4], uint(8)), init: mem.fill(4, uint(8, 0x22)))
    mixed_r = reg("mixed_r", mem([2], arr([3], uint(8))), init: mem.fill(2, arr.fill(3, uint(8, 0))))

    packed_word <= packed_r[idx]
    memory_word <= memory_r[idx]
    mixed_word <= mixed_r[0][1]

    always_comb do
      # A uint behaves like a stream of bits.
      parity <= mask_r.sv_take(4).sv_reduce { |a, b| a ^ b }
      selected_bits <= mask_r
        .sv_take(8)
        .sv_select { |_, i| i.even? }
        .sv_map { |v, _i| v }

      # Packed and unpacked collections can both be mapped into a packed result.
      packed_slice <= packed_r
        .sv_take(4)
        .sv_select { |_, i| i < 2 }
        .sv_map { |v, _i| v }
      mem_slice <= memory_r
        .sv_take(4)
        .sv_select { |_, i| i < 2 }
        .sv_map { |v, _i| v }

      # Mixed shapes can be traversed one dimension at a time.
      mixed_slice <= mixed_r
        .sv_take(2)
        .sv_map { |row, _i| row.sv_take(2).sv_map { |v, _j| v } }
    end

    # The explicit `(clock, reset)` form supports negedge / active-low domains.
    always_ff(clk.neg, rst_n.neg) do
      svif(update) do
        mask_r
          .sv_take(8)
          .sv_select { |_, i| i.even? }
          .sv_foreach { |v, i| v <= mask_old[i] }

        memory_r
          .sv_take(4)
          .sv_select { |_, i| i < 2 }
          .sv_foreach { |v, i| v <= packed_r[i] }

        mixed_r.sv_take(2).sv_foreach do |row, i|
          row
            .sv_take(3)
            .sv_select { |_, j| j.even? }
            .sv_foreach { |_v, j| mixed_r[i][j] <= memory_r[j] }
        end
      end
    end
  end
end

storage_streams = StorageStreams.new
output_path = File.join(__dir__, "..", "build", "rtl", "storage_streams.sv")

storage_streams.to_sv("-")
storage_streams.to_sv(output_path)
warn "Written to #{output_path}"
