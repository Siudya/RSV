# frozen_string_literal: true

module RSV
  # Builder used inside alwaysFf and alwaysComb blocks.
  # Provides nbAssign, assign, ifStmt, elsifStmt, elseStmt.
  class ProceduralBuilder
    attr_reader :stmts

    def initialize
      @stmts   = []
      @lastIf  = nil
    end

    # Non-blocking assignment:  lhs <= rhs;
    def nbAssign(lhs, rhs)
      @stmts  << NbAssign.new(lhs, rhs)
      @lastIf  = nil
    end

    # Blocking assignment:  lhs = rhs;
    def assign(lhs, rhs)
      @stmts  << BlockingAssign.new(lhs, rhs)
      @lastIf  = nil
    end

    # if (<cond>) begin ... end
    def ifStmt(cond, &block)
      builder = ProceduralBuilder.new
      builder.instance_eval(&block) if block_given?
      stmt    = IfStmt.new(cond, builder.stmts)
      @stmts << stmt
      @lastIf = stmt
    end

    # else if (<cond>) begin ... end  — must follow ifStmt or elsifStmt
    def elsifStmt(cond, &block)
      raise "elsifStmt called without a preceding ifStmt" unless @lastIf

      builder = ProceduralBuilder.new
      builder.instance_eval(&block) if block_given?
      @lastIf.addElsif(cond, builder.stmts)
    end

    # else begin ... end  — must follow ifStmt or elsifStmt
    def elseStmt(&block)
      raise "elseStmt called without a preceding ifStmt" unless @lastIf

      builder = ProceduralBuilder.new
      builder.instance_eval(&block) if block_given?
      @lastIf.setElse(builder.stmts)
      @lastIf = nil
    end
  end
end
