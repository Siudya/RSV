# frozen_string_literal: true
# examples/sv_plugin_demo.rb
#
# Demonstrates sv_plugin for embedding raw SystemVerilog code.
#
# Covered syntax:
# - sv_plugin at module level (top-level statements)
# - sv_plugin inside always_ff (procedural context)
# - Multi-line sv_plugin with heredoc
# - Combining sv_plugin with normal RSV declarations
#
# Run:
#   ruby examples/sv_plugin_demo.rb

$LOAD_PATH.unshift(File.join(__dir__, "..", "lib"))
require "rsv"
include RSV

class SvPluginDemo < ModuleDef
  def build
    clk = input("clk", clock)
    rst = input("rst", reset)
    din = input("din", uint(8))
    dout = output("dout", uint(8))
    dbg = output("dbg", uint(8))

    r = reg("r", uint(8), init: 0)
    dout <= r

    # Module-level inline SV: custom assertion block
    sv_plugin <<~SV
      // synopsys translate_off
      always @(posedge clk) begin
        assert (din != 8'hFF) else $error("din overflow at %0t", $time);
      end
      // synopsys translate_on
    SV

    # Module-level inline SV: function definition + assign
    sv_plugin <<~SV
      function automatic [7:0] dbg_xform(input [7:0] v);
        return v ^ 8'hA5;
      endfunction
    SV
    sv_plugin "assign dbg = dbg_xform(din);"

    with_clk_and_rst(clk, rst)
    always_ff do
      # Procedural-level inline SV: simulation display
      sv_plugin '// synthesis translate_off'
      sv_plugin '$display("r=%h din=%h", r, din);'
      sv_plugin '// synthesis translate_on'
      r <= din
    end
  end
end

output_path = File.join(__dir__, "..", "build", "rtl", "sv_plugin_demo.sv")

demo = SvPluginDemo.new("sv_plugin_demo")
demo.to_sv("-")
demo.to_sv(output_path)
warn "Written to #{output_path}"
