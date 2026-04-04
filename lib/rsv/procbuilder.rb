# frozen_string_literal: true

module RSV
  # Builder used inside always_ff and always_comb blocks.
  # Provides nbAssign, assign, ifStmt, elsifStmt, elseStmt.
  class ProceduralBuilder
    attr_reader :stmts

    def initialize
      @stmts   = []
      @lastIf  = nil
    end

    def build(&block)
      return self unless block_given?

      RSV.withProceduralBuilder(self) do
        instance_eval(&block)
      end

      self
    end

    # Non-blocking assignment:  lhs <= rhs;
    def nbAssign(lhs, rhs)
      @stmts  << NbAssign.new(RSV.normalizeExpr(lhs), RSV.normalizeExpr(rhs))
      @lastIf  = nil
    end
    alias nb_assign nbAssign

    # Blocking assignment:  lhs = rhs;
    def assign(lhs, rhs)
      @stmts  << BlockingAssign.new(RSV.normalizeExpr(lhs), RSV.normalizeExpr(rhs))
      @lastIf  = nil
    end

    # if (<cond>) begin ... end
    def ifStmt(cond, &block)
      builder = ProceduralBuilder.new
      builder.build(&block)
      stmt    = IfStmt.new(RSV.normalizeExpr(cond), builder.stmts)
      @stmts << stmt
      @lastIf = stmt
    end
    alias if_stmt ifStmt

    def when_(cond, &block)
      ifStmt(cond, &block)
    end

    # else if (<cond>) begin ... end  — must follow ifStmt or elsifStmt
    def elsifStmt(cond, &block)
      raise "elsifStmt called without a preceding ifStmt" unless @lastIf

      builder = ProceduralBuilder.new
      builder.build(&block)
      @lastIf.addElsif(RSV.normalizeExpr(cond), builder.stmts)
    end
    alias elsif_stmt elsifStmt

    # else begin ... end  — must follow ifStmt or elsifStmt
    def elseStmt(&block)
      raise "elseStmt called without a preceding ifStmt" unless @lastIf

      builder = ProceduralBuilder.new
      builder.build(&block)
      @lastIf.setElse(builder.stmts)
      @lastIf = nil
    end
    alias else_stmt elseStmt
  end
end
