# frozen_string_literal: true
# examples/manual_dedup.rb
#
# Demonstrates manual module deduplication with `definition(...)` +
# `instance(...)`, while wiring one child module into another through an
# auto-generated parent-local wire.
#
# Covered syntax:
# - `Counter.definition(...)` + `instance(...)`
# - submodule-to-submodule electrical connections via an auto-generated wire
# - left and right assignment forms for instance connections
# - unique dependency emission for deduplicated definition handles
#
# Run:
#   ruby examples/manual_dedup.rb

$LOAD_PATH.unshift(File.join(__dir__, "..", "lib"))
require "rsv"

class ManualDedupCounter < RSV::ModuleDef
  def build(width: 8)
    # The caller may request different widths, but this example intentionally
    # elaborates one shared 8-bit template so `definition(...)` reuses the same
    # cached handle.
    parameter "WIDTH", 8

    din = input("din", uint("WIDTH"))
    dout = output("dout", uint("WIDTH"))

    dout <= din
  end
end

class ManualDedupTop < RSV::ModuleDef
  def build(stage_a_def:, stage_b_def:)
    input_a = input("input_a", uint(8))
    output_z = output("output_z", uint(8))

    stage_a = instance(stage_a_def, inst_name: "u_stage_a")
    stage_b = instance(stage_b_def, inst_name: "u_stage_b")

    stage_a.din <= input_a
    stage_a.dout <= stage_b.din
    stage_b.dout >= output_z
  end
end

def rtl_output_path(module_name)
  file_name = module_name.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
  File.join(__dir__, "..", "build", "rtl", "#{file_name}.sv")
end

stage_a_def = ManualDedupCounter.definition(width: 8)
stage_b_def = ManualDedupCounter.definition(width: 16)
top = ManualDedupTop.new(stage_a_def: stage_a_def, stage_b_def: stage_b_def)
top_output_path = rtl_output_path(top.module_name)

top.to_sv("-")
[stage_a_def, stage_b_def].uniq.each do |counter_def|
  counter_def.to_sv(rtl_output_path(counter_def.module_name))
end
top.to_sv(top_output_path)
warn "Written to #{rtl_output_path(stage_a_def.module_name)}"
warn "Written to #{top_output_path}"
