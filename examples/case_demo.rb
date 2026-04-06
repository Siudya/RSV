# frozen_string_literal: true
# examples/case_demo.rb
#
# Demonstrates case/casez/casex statements and unique/priority qualifiers.
#
# Covered syntax:
# - svcase: plain case statement
# - svcasez: casez statement (with ? wildcard)
# - svcasex: casex statement
# - unique/priority qualifiers on case and if
# - Multi-value is() branches
# - fallin (default) branch
# - Case inside always_ff (non-blocking assigns)
# - Chained svif/svelif/svelse
#
# Run:
#   xmake rtl -f case_demo

$LOAD_PATH.unshift(File.join(__dir__, "..", "lib"))
require "rsv"
include RSV

class CaseDemo < ModuleDef
  def build
    let :clk, input(clock)
    let :rst, input(reset)
    let :opcode, input(uint(3))
    let :mode, input(uint(4))
    let :data_in, input(uint(8))

    let :alu_out, output(uint(8))
    let :state_out, output(uint(8))
    let :flag, output(bit)
    let :sel_out, output(uint(8))

    let :alu_w, wire(uint(8))
    let :flag_w, wire(bit)
    let :sel_w, wire(uint(8))
    let :state_r, reg(uint(8), init: 0)

    alu_out <= alu_w
    state_out <= state_r
    flag <= flag_w
    sel_out <= sel_w

    # plain case in always_comb
    always_comb do
      svcase(opcode) do
        is(0) { alu_w <= data_in }
        is(1) { alu_w <= data_in + 1 }
        is(2) { alu_w <= data_in - 1 }
        is(3, 4) { alu_w <= data_in << 1 }
        fallin { alu_w <= 0 }
      end
    end

    # unique casez with ? wildcard patterns
    always_comb do
      svcasez(mode, unique: true) do
        is("4'b???1") { flag_w <= 1 }
        is("4'b??10") { flag_w <= 1 }
        is("4'b?100") { flag_w <= 0 }
        is("4'b1000") { flag_w <= 0 }
        fallin { flag_w <= 0 }
      end
    end

    # case inside always_ff (non-blocking assigns)
    with_clk_and_rst(clk, rst)
    always_ff do
      svcase(opcode) do
        is(0) { state_r <= data_in }
        is(1) { state_r <= state_r + 1 }
        fallin { state_r <= state_r }
      end
    end

    # compact chained unique if / svelif / svelse
    always_comb do
      svif(opcode.eq(0), unique: true) { sel_w <= data_in }
      .svelif(opcode.eq(1)) { sel_w <= data_in + 1 }
      .svelse { sel_w <= 0 }
    end
  end
end

demo = CaseDemo.new

RSV::App.main(demo)
