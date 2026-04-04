# frozen_string_literal: true

module RSV
  # Represents an input / output / inout port declaration.
  class PortDecl
    attr_reader :dir, :name, :width, :signed

    def initialize(dir, name, width, signed)
      @dir    = dir    # :input | :output | :inout
      @name   = name
      @width  = width  # Integer, String (e.g. "WIDTH"), or "1"
      @signed = signed
    end
  end

  # Represents a parameter declaration.
  class ParamDecl
    attr_reader :name, :value, :param_type

    def initialize(name, value, param_type)
      @name       = name
      @value      = value
      @param_type = param_type  # e.g. "int", "logic [7:0]", or nil
    end
  end

  # Represents a local logic signal declaration.
  class LogicDecl
    attr_reader :name, :width, :signed

    def initialize(name, width, signed)
      @name   = name
      @width  = width
      @signed = signed
    end
  end

  # Continuous assignment:  assign <lhs> = <rhs>;
  AssignStmt     = Struct.new(:lhs, :rhs)

  # Non-blocking assignment:  <lhs> <= <rhs>;
  NbAssign       = Struct.new(:lhs, :rhs)

  # Blocking assignment:  <lhs> = <rhs>;
  BlockingAssign = Struct.new(:lhs, :rhs)

  # always_ff @(<sensitivity>) begin ... end
  AlwaysFF       = Struct.new(:sensitivity, :body)

  # always_comb begin ... end
  AlwaysComb     = Struct.new(:body)

  # Procedural if / else-if / else statement.
  class IfStmt
    attr_reader :cond, :then_stmts, :elsif_clauses, :else_stmts

    def initialize(cond, then_stmts)
      @cond          = cond
      @then_stmts    = then_stmts
      @elsif_clauses = []   # Array of { cond:, stmts: }
      @else_stmts    = nil
    end

    def add_elsif(cond, stmts)
      @elsif_clauses << { cond: cond, stmts: stmts }
    end

    def set_else(stmts)
      @else_stmts = stmts
    end
  end

  # Module instantiation.
  class Instance
    attr_reader :module_name, :inst_name, :params, :connections

    def initialize(module_name, inst_name, params:, connections:)
      @module_name  = module_name
      @inst_name    = inst_name
      @params       = params       # Hash: param_name (String) => value
      @connections  = connections  # Hash: port_name  (String) => signal
    end
  end
end
