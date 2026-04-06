# frozen_string_literal: true
# examples/auto_dedup.rb
#
# Demonstrates automatic module deduplication when repeated submodule
# instantiations elaborate to the same SV template, while also wiring one
# child module into another through an auto-generated parent-local wire.
#
# Covered syntax:
# - automatic dedup via `ModuleDef.new(inst_name: ...)`
# - submodule-to-submodule electrical connections via an auto-generated wire
# - left and right assignment forms for instance connections
# - unique dependency emission for deduplicated module objects
#
# Run:
#   xmake rtl -f aut

$LOAD_PATH.unshift(File.join(__dir__, "..", "lib"))
require "rsv"

class AutoDedupCounter < RSV::ModuleDef
  def build(width: 8)
    din = input("din", uint(width))
    dout = output("dout", uint(width))

    dout <= din
  end
end

class AutoDedupTop < RSV::ModuleDef
  def build
    input_a = input("input_a", uint(8))
    output_z = output("output_z", uint(8))

    stage_a = AutoDedupCounter.new(inst_name: "u_stage_a", width: 8)
    stage_b = AutoDedupCounter.new(inst_name: "u_stage_b", width: 8)

    stage_a.din <= input_a
    stage_a.dout <= stage_b.din
    stage_b.dout >= output_z
  end
end

def rtl_output_path(module_name)
  file_name = module_name.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
  File.join(__dir__, "..", "build", "rtl", "#{file_name}.sv")
end

counter_defs = [
  AutoDedupCounter.new(width: 8)
].uniq { |definition| definition.module_name }

top = AutoDedupTop.new

RSV::App.main(top)
