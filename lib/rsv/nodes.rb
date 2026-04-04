# frozen_string_literal: true

module RSV
  module ExprOps
    def +(other)
      BinaryExpr.new(self, :+, RSV.normalizeExpr(other))
    end

    def -(other)
      BinaryExpr.new(self, :-, RSV.normalizeExpr(other))
    end

    def &(other)
      BinaryExpr.new(self, :&, RSV.normalizeExpr(other))
    end

    def |(other)
      BinaryExpr.new(self, :|, RSV.normalizeExpr(other))
    end

    def ^(other)
      BinaryExpr.new(self, :^, RSV.normalizeExpr(other))
    end

    def <(other)
      BinaryExpr.new(self, :<, RSV.normalizeExpr(other))
    end

    def >(other)
      BinaryExpr.new(self, :>, RSV.normalizeExpr(other))
    end

    def >=(other)
      BinaryExpr.new(self, :>=, RSV.normalizeExpr(other))
    end

    def [](index)
      IndexExpr.new(self, RSV.normalizeExpr(index))
    end
  end

  module AssignableExpr
    def <=(rhs)
      builder = RSV.currentProceduralBuilder
      raise "non-blocking assignment is only valid inside procedural blocks" unless builder

      builder.nbAssign(self, rhs)
    end
  end

  # Typed signal declaration input used by the public DSL.
  class SignalSpec
    attr_reader :name, :width, :signed, :init

    def initialize(name, width:, signed: false, init: nil)
      @name   = name
      @width  = width
      @signed = signed
      @init   = init
    end
  end

  class RawExpr
    include ExprOps

    attr_reader :source

    def initialize(source)
      @source = source
    end

    def to_s
      @source
    end
  end

  class LiteralExpr
    include ExprOps

    attr_reader :value, :width, :format

    def initialize(value, width: nil, format: :decimal)
      @value  = value
      @width  = width
      @format = format
    end

    def withWidth(width)
      LiteralExpr.new(@value, width: width, format: @format)
    end

    def to_s
      @value.to_s
    end
  end

  class BinaryExpr
    include ExprOps

    attr_reader :lhs, :op, :rhs

    def initialize(lhs, op, rhs)
      @lhs = RSV.normalizeExpr(lhs)
      @op  = op
      @rhs = RSV.normalizeExpr(rhs)
    end
  end

  class IndexExpr
    include ExprOps
    include AssignableExpr

    attr_reader :base, :index

    def initialize(base, index)
      @base  = RSV.normalizeExpr(base)
      @index = RSV.normalizeExpr(index)
    end

    def width
      1
    end

    def baseName
      @base.baseName if @base.respond_to?(:baseName)
    end
  end

  # Opaque handle returned from declarations and used to reference a signal.
  class SignalHandler
    include ExprOps
    include AssignableExpr

    attr_reader :name, :width, :signed, :kind, :init

    def initialize(name, width: 1, signed: false, kind: nil, init: nil)
      @name   = name
      @width  = width
      @signed = signed
      @kind   = kind
      @init   = init
    end

    def withWidth(width)
      SignalHandler.new(@name, width: width, signed: @signed, kind: @kind, init: @init)
    end

    def to_s
      @name
    end

    def baseName
      @name
    end
  end

  # Represents an input / output / inout port declaration.
  class PortDecl
    attr_reader :dir, :name, :width, :signed

    def initialize(dir, signal)
      @dir    = dir    # :input | :output | :inout
      @name   = signal.name
      @width  = signal.width  # Integer or String (e.g. "WIDTH")
      @signed = signal.signed
    end
  end

  # Represents a parameter declaration.
  class ParamDecl
    attr_reader :name, :value, :paramType

    def initialize(name, value, paramType)
      @name      = name
      @value     = value
      @paramType = paramType
    end
  end

  # Represents a local wire / logic / reg signal declaration.
  class LocalDecl
    attr_reader :kind, :name, :width, :signed, :init, :resetInit

    def initialize(kind, signal, init: signal.init, resetInit: nil)
      @kind      = kind
      @name      = signal.name
      @width     = signal.width
      @signed    = signal.signed
      @init      = init
      @resetInit = resetInit
    end

    def svKind
      @kind == :reg ? :logic : @kind
    end

    def resettable?
      !@resetInit.nil?
    end
  end

  class ElaboratedModule
    attr_reader :name, :params, :ports, :locals, :stmts

    def initialize(name, params:, ports:, locals:, stmts:)
      @name   = name
      @params = params
      @ports  = ports
      @locals = locals
      @stmts  = stmts
    end
  end

  # Continuous assignment: assign <lhs> = <rhs>;
  AssignStmt     = Struct.new(:lhs, :rhs)
  NbAssign       = Struct.new(:lhs, :rhs)
  BlockingAssign = Struct.new(:lhs, :rhs)

  class AlwaysFF
    attr_reader :body, :sensitivity, :clock, :reset

    def initialize(body, sensitivity: nil, clock: nil, reset: nil)
      @body        = body
      @sensitivity = sensitivity
      @clock       = clock
      @reset       = reset
    end

    def domainDriven?
      !@clock.nil? && !@reset.nil?
    end
  end

  AlwaysLatch = Struct.new(:body)
  AlwaysComb = Struct.new(:body)

  # Procedural if / else-if / else statement.
  class IfStmt
    attr_reader :cond, :thenStmts, :elsifClauses, :elseStmts

    def initialize(cond, thenStmts)
      @cond         = cond
      @thenStmts    = thenStmts
      @elsifClauses = []   # Array of { cond:, stmts: }
      @elseStmts    = nil
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
      @moduleName  = moduleName
      @instName    = instName
      @params      = params
      @connections = connections
    end
  end

  def self.normalizeSignalSpec(signal)
    return signal if signal.is_a?(SignalSpec)

    raise TypeError, "signal declaration expects RSV::SignalSpec, got #{signal.class}"
  end

  def self.normalizeExpr(operand)
    case operand
    when SignalHandler, RawExpr, LiteralExpr, BinaryExpr, IndexExpr
      operand
    when String
      RawExpr.new(operand)
    when Numeric
      LiteralExpr.new(operand)
    else
      raise TypeError, "signal operand expects String, Numeric, RSV::SignalHandler, or RSV expression, got #{operand.class}"
    end
  end

  class << self
    alias normalizeOperand normalizeExpr
  end

  def self.binaryExprWidth(op, lhsWidth, rhsWidth)
    case op
    when :<, :>, :>=
      1
    when :+, :-, :&, :|, :^
      [lhsWidth, rhsWidth].compact.max
    else
      [lhsWidth, rhsWidth].compact.max
    end
  end

  def self.inferExprWidth(expr)
    expr = normalizeExpr(expr)

    case expr
    when SignalHandler
      expr.width
    when RawExpr
      nil
    when LiteralExpr
      expr.width
    when BinaryExpr
      lhsWidth = inferExprWidth(expr.lhs)
      rhsWidth = inferExprWidth(expr.rhs)
      binaryExprWidth(expr.op, lhsWidth, rhsWidth)
    when IndexExpr
      1
    else
      nil
    end
  end

  def self.resetInitExpr(init, width)
    return normalizeExpr(init) if init.is_a?(String)

    LiteralExpr.new(init, width: width, format: :hex)
  end

  def self.withProceduralBuilder(builder)
    stack = Thread.current[:rsv_procedural_builders] ||= []
    stack << builder
    yield
  ensure
    stack.pop
  end

  def self.currentProceduralBuilder
    stack = Thread.current[:rsv_procedural_builders]
    stack&.last
  end
end
