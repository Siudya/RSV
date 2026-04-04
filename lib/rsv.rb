# frozen_string_literal: true

require_relative "rsv/nodes"
require_relative "rsv/procedural_builder"
require_relative "rsv/module_def"
require_relative "rsv/emitter"

# RSV — Ruby SystemVerilog Generator
#
# A lightweight Ruby DSL for generating readable, semantic-preserving
# SystemVerilog.  Use RSV::ModuleDef as the primary entry point.
module RSV
  VERSION = "0.1.0"
end
