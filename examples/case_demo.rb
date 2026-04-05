# frozen_string_literal: true
# examples/case_demo.rb
#
# Demonstrates case/casez/casex statements and unique/priority qualifiers.
#
# Covered syntax:
# - svcase: plain case statement
# - svcasez: casez statement
# - svcasex: casex statement
# - unique/priority qualifiers on case and if
# - Multi-value when_ branches
# - default_ branch
# - Case inside always_ff (non-blocking assigns)
#
# Run:
#   xmake rtl -f case_demo

$LOAD_PATH.unshift(File.join(__dir__, "..", "lib"))
require "rsv"
include RSV

class CaseDemo < ModuleDef
  def build
    clk = input("clk", clock)
    rst = input("rst", reset)
    opcode = input("opcode", uint(3))
    mode = input("mode", uint(4))
    data_in = input("data_in", uint(8))

    alu_out = output("alu_out", uint(8))
    state_out = output("state_out", uint(8))
    flag = output("flag", bit)
    sel_out = output("sel_out", uint(8))

    alu_w = wire("alu_w", uint(8))
    flag_w = wire("flag_w", bit)
    sel_w = wire("sel_w", uint(8))
    state_r = reg("state_r", uint(8), init: 0)

    alu_out <= alu_w
    state_out <= state_r
    flag <= flag_w
    sel_out <= sel_w

    # plain case in always_comb
    always_comb do
      svcase(opcode) do
        when_(0) { alu_w <= data_in }
        when_(1) { alu_w <= data_in + 1 }
        when_(2) { alu_w <= data_in - 1 }
        when_(3, 4) { alu_w <= data_in << 1 }
        default_ { alu_w <= 0 }
      end
    end

    # unique casez with one-hot-style matching
    always_comb do
      svcasez(mode, unique: true) do
        when_(0b0001) { flag_w <= 1 }
        when_(0b0010) { flag_w <= 1 }
        when_(0b0100) { flag_w <= 0 }
        when_(0b1000) { flag_w <= 0 }
        default_ { flag_w <= 0 }
      end
    end

    # case inside always_ff (non-blocking assigns)
    with_clk_and_rst(clk, rst)
    always_ff do
      svcase(opcode) do
        when_(0) { state_r <= data_in }
        when_(1) { state_r <= state_r + 1 }
        default_ { state_r <= state_r }
      end
    end

    # unique if / priority if
    always_comb do
      svif(opcode.eq(0), unique: true) do
        sel_w <= data_in
      end
      svelif(opcode.eq(1)) do
        sel_w <= data_in + 1
      end
      svelse do
        sel_w <= 0
      end
    end
  end
end

demo = CaseDemo.new
output_path = File.join(__dir__, "..", "build", "rtl", "case_demo.sv")

demo.to_sv("-")
demo.to_sv(output_path)
warn "Written to #{output_path}"
