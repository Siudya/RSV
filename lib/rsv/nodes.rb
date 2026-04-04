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
    attr_reader :name, :value, :paramType

    def initialize(name, value, paramType)
      @name      = name
      @value     = value
      @paramType = paramType  # e.g. "int", "logic [7:0]", or nil
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
    attr_reader :cond, :thenStmts, :elsifClauses, :elseStmts

    def initialize(cond, thenStmts)
      @cond          = cond
      @thenStmts     = thenStmts
      @elsifClauses  = []   # Array of { cond:, stmts: }
      @elseStmts     = nil
    end

    def addElsif(cond, stmts)
      @elsifClauses << { cond: cond, stmts: stmts }
    end

    def setElse(stmts)
      @elseStmts = stmts
    end
  end

  # Module instantiation.
  class Instance
    attr_reader :moduleName, :instName, :params, :connections

    def initialize(moduleName, instName, params:, connections:)
      @moduleName   = moduleName
      @instName     = instName
      @params       = params       # Hash: param_name (String) => value
      @connections  = connections  # Hash: port_name  (String) => signal
    end
  end
end
