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
    # The caller may request different widths, but this example intentionally
    # elaborates one shared 8-bit template so automatic dedup can collapse the
    # repeated module objects.
    parameter "WIDTH", 8

    din = input("din", uint("WIDTH"))
    dout = output("dout", uint("WIDTH"))

    dout <= din
  end
end

class AutoDedupTop < RSV::ModuleDef
  def build
    input_a = input("input_a", uint(8))
    output_z = output("output_z", uint(8))

    stage_a = AutoDedupCounter.new(inst_name: "u_stage_a", width: 8)
    stage_b = AutoDedupCounter.new(inst_name: "u_stage_b", width: 16)

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
  AutoDedupCounter.new(width: 8),
  AutoDedupCounter.new(width: 16)
].uniq { |definition| definition.module_name }

top = AutoDedupTop.new
top_output_path = rtl_output_path(top.module_name)

top.to_sv("-")
counter_defs.each do |counter_def|
  counter_def.to_sv(rtl_output_path(counter_def.module_name))
end
top.to_sv(top_output_path)
counter_defs.each do |counter_def|
  warn "Written to #{rtl_output_path(counter_def.module_name)}"
end
warn "Written to #{top_output_path}"
