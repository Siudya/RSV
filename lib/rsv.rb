# frozen_string_literal: true

require_relative "rsv/mixins"
require_relative "rsv/nodes"
require_relative "rsv/procbuilder"
require_relative "rsv/validator"
require_relative "rsv/moddef"
require_relative "rsv/bundledef"

require_relative "rsv/elaborator"
require_relative "rsv/emitter"
require_relative "rsv/svimport"
require_relative "rsv/vwrapper"
require_relative "rsv/registry"

# RSV — Ruby SystemVerilog Generator
#
# A lightweight Ruby DSL for generating readable, semantic-preserving
# SystemVerilog.  Use RSV::ModuleDef as the primary entry point.
module RSV
  VERSION = "0.1.0"

  # 将所有已 elaborate 的模块导出到指定目录
  def self.export_all(dir)
    ElaborationRegistry.export_all(dir)
  end
end
