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
#   xmake rtl -f man

$LOAD_PATH.unshift(File.join(__dir__, "..", "lib"))
require "rsv"

class ManualDedupCounter < RSV::ModuleDef
  def build(width: 8)
    din = input("din", uint(width))
    dout = output("dout", uint(width))

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

stage_a_def = ManualDedupCounter.definition(width: 8)
stage_b_def = ManualDedupCounter.definition(width: 8)
top = ManualDedupTop.new(stage_a_def: stage_a_def, stage_b_def: stage_b_def)

RSV::App.main(top)
