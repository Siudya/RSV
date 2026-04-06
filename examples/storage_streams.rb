# frozen_string_literal: true
# examples/storage_streams.rb
#
# Demonstrates shaped storage declarations and the stream-view API across scalar
# and unpacked shapes.
#
# Covered syntax:
# - `mem(...)`, nested shapes, and fill helpers
# - indexing memories and nested shapes
# - `sv_take`, `sv_select`, `sv_foreach`, `sv_reduce`, `sv_map`
# - nested stream traversal over multi-dimensional shapes
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

    memory_word = output("memory_word", uint(8))
    mixed_word = output("mixed_word", uint(8))
    parity = output("parity", bit)
    selected_bits = output("selected_bits", uint(4))
    mem_slice = output("mem_slice", mem([2], uint(8)))

    # Unpacked memories and nested memories. The init helpers produce reset
    # values for the auto-generated reset branch.
    mask_r = reg("mask_r", uint(16), init: 0)
    memory_r = reg("memory_r", mem([4], uint(8)), init: mem.fill(4, uint(8, 0x22)))
    mixed_r = reg("mixed_r", mem([2], mem([3], uint(8))), init: mem.fill(2, mem.fill(3, uint(8, 0))))

    memory_word <= memory_r[idx]
    mixed_word <= mixed_r[0][1]

    always_comb do
      # A uint behaves like a stream of bits.
      parity <= mask_r.sv_take(4).sv_reduce { |a, b| a ^ b }
      selected_bits <= mask_r
        .sv_take(8)
        .sv_select { |_, i| i.even? }
        .sv_map { |v, _i| v }

      # Unpacked collections can be mapped into a packed result.
      mem_slice <= memory_r
        .sv_take(4)
        .sv_select { |_, i| i < 2 }
        .sv_map { |v, _i| v }
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
          .sv_foreach { |v, i| v <= memory_r[i + 2] }

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

RSV::App.main(storage_streams)
