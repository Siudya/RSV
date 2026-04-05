# frozen_string_literal: true
# examples/mux_cases.rb
#
# Demonstrates the three mux helpers:
# - `mux(...)` for a plain ternary expression
# - `mux1h(...)` for a one-hot casez tree
# - `muxp(...)` for a priority casez tree in both LSB-first and MSB-first modes
#
# Run:
#   xmake rtl -f mux

$LOAD_PATH.unshift(File.join(__dir__, "..", "lib"))
require "rsv"

class MuxCases < RSV::ModuleDef
  def build
    ternary_sel = input("ternary_sel", bit)
    sel_1h = input("sel_1h", uint(4))
    sel_p = input("sel_p", uint(4))
    a = input("a", uint(8))
    b = input("b", uint(8))
    dats = input("dats", mem([4], uint(8)))

    ternary_o = output("ternary_o", uint(8))
    one_hot_o = output("one_hot_o", uint(8))
    priority_lsb_o = output("priority_lsb_o", uint(8))
    priority_msb_o = output("priority_msb_o", uint(8))

    ternary_o <= mux(ternary_sel, a, b)

    always_comb do
      one_hot_o <= mux1h(sel_1h, dats)
      priority_lsb_o <= muxp(sel_p, dats)
      priority_msb_o <= muxp(sel_p, dats, lsb_first: false)
    end
  end
end

mux_cases = MuxCases.new
output_path = File.join(__dir__, "..", "build", "rtl", "mux_cases.sv")

mux_cases.to_sv("-")
mux_cases.to_sv(output_path)
warn "Written to #{output_path}"
