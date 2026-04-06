# frozen_string_literal: true
# examples/macro_demo.rb
#
# Demonstrates SV preprocessor macro support.
#
# Covered syntax:
# - sv_def / sv_undef for `define / `undef
# - sv_ifdef / sv_ifndef with sv_elif_def / sv_else_def chains
# - sv_dref for macro value references (`MACRO_NAME)
#
# Run:
#   xmake rtl -f mac

$LOAD_PATH.unshift(File.join(__dir__, "..", "lib"))
require "rsv"

class MacroDemo < RSV::ModuleDef
  def build
    sv_def "DEFAULT_WIDTH", "8"

    input :clk, bit
    input :rst, bit
    input :mode, uint(2)
    output :out, uint(8)

    reg :count_r, uint(8), init: 0

    with_clk_and_rst(clk, rst)
    always_ff do
      svif(mode.eq(0)) do
        count_r <= count_r + sv_dref("DEFAULT_WIDTH")
      end
      svelse do
        count_r <= count_r + 1
      end
    end

    sv_ifdef("SIM") do
      out <= count_r
    end.sv_else_def do
      out <= count_r + 1
    end

    sv_undef "DEFAULT_WIDTH"
  end
end

mod = MacroDemo.new

RSV::App.main(mod)
