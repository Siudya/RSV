# frozen_string_literal: true

require_relative "rsv/mixins"
require_relative "rsv/nodes"
require_relative "rsv/procbuilder"
require_relative "rsv/validator"
require_relative "rsv/moddef"
require_relative "rsv/bundledef"
require_relative "rsv/interfacedef"
require_relative "rsv/elaborator"
require_relative "rsv/emitter"
require_relative "rsv/svimport"
require_relative "rsv/vwrapper"

# RSV — Ruby SystemVerilog Generator
#
# A lightweight Ruby DSL for generating readable, semantic-preserving
# SystemVerilog.  Use RSV::ModuleDef as the primary entry point.
module RSV
  VERSION = "0.1.0"
end
