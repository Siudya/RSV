# frozen_string_literal: true

module RSV
  # Builder used inside always_ff, always_comb, and always_latch blocks.
  class ProceduralBuilder
    attr_reader :stmts

    def initialize(assign_context:)
      @stmts   = []
      @last_if  = nil
      @assign_context = assign_context
    end

    def build(&block)
      return self unless block_given?

      RSV.with_procedural_builder(self) do
        instance_eval(&block)
      end

      self
    end

    # if (<cond>) begin ... end
    def if_stmt(cond, qualifier: nil, &block)
      builder = ProceduralBuilder.new(assign_context: @assign_context)
      builder.build(&block)
      stmt    = IfStmt.new(RSV.normalize_expr(cond), builder.stmts, qualifier: qualifier)
      @stmts << stmt
      @last_if = stmt
      IfChain.new(self, stmt)
    end

    def svif(cond, unique: false, priority: false, &block)
      qual = unique ? :unique : (priority ? :priority : nil)
      if_stmt(cond, qualifier: qual, &block)
    end

    # else if (<cond>) begin ... end  — must follow if_stmt or elsif_stmt
    def elsif_stmt(cond, &block)
      raise "elsif_stmt called without a preceding if_stmt" unless @last_if

      builder = ProceduralBuilder.new(assign_context: @assign_context)
      builder.build(&block)
      @last_if.add_elsif(RSV.normalize_expr(cond), builder.stmts)
      IfChain.new(self, @last_if)
    end
    alias svelif elsif_stmt

    # else begin ... end  — must follow if_stmt or elsif_stmt
    def else_stmt(&block)
      raise "else_stmt called without a preceding if_stmt" unless @last_if

      builder = ProceduralBuilder.new(assign_context: @assign_context)
      builder.build(&block)
      @last_if.set_else(builder.stmts)
      @last_if = nil
    end
    alias svelse else_stmt

    # case (expr) ... endcase
    def svcase(expr, unique: false, priority: false, &block)
      qual = unique ? :unique : (priority ? :priority : nil)
      case_builder = CaseBuilder.new(@assign_context, RSV.normalize_expr(expr), case_kind: :case, qualifier: qual)
      case_builder.build(&block)
      @stmts << case_builder.to_stmt
      @last_if = nil
    end

    # casez (expr) ... endcase
    def svcasez(expr, unique: false, priority: false, &block)
      qual = unique ? :unique : (priority ? :priority : nil)
      case_builder = CaseBuilder.new(@assign_context, RSV.normalize_expr(expr), case_kind: :casez, qualifier: qual)
      case_builder.build(&block)
      @stmts << case_builder.to_stmt
      @last_if = nil
    end

    # casex (expr) ... endcase
    def svcasex(expr, unique: false, priority: false, &block)
      qual = unique ? :unique : (priority ? :priority : nil)
      case_builder = CaseBuilder.new(@assign_context, RSV.normalize_expr(expr), case_kind: :casex, qualifier: qual)
      case_builder.build(&block)
      @stmts << case_builder.to_stmt
      @last_if = nil
    end

    def cat(*parts)
      CatExpr.new(parts)
    end

    def fill(n, part)
      FillExpr.new(n, part)
    end

    def mux1h(sel1h, dats)
      Mux1hExpr.new(sel1h, dats)
    end

    def muxp(sel, dats, lsb_first: true)
      MuxpExpr.new(sel, dats, lsb_first: lsb_first)
    end

    def mux(sel, a, b)
      MuxExpr.new(sel, a, b)
    end

    def sv_dref(name)
      MacroRef.new(name.to_s)
    end

    def sv_plugin(code)
      @stmts << SvPlugin.new(code.to_s)
    end

    private

    def append_assignment(lhs, rhs)
      # Expand mux1h/muxp expressions into MuxCaseStmt
      case rhs
      when Mux1hExpr
        normalized_lhs = RSV.normalize_expr(lhs)
        stmt = MuxCaseStmt.new(normalized_lhs, rhs.sel, rhs.dats, case_type: :unique)
        @stmts << stmt
        @last_if = nil
        return stmt
      when MuxpExpr
        normalized_lhs = RSV.normalize_expr(lhs)
        stmt = MuxCaseStmt.new(normalized_lhs, rhs.sel, rhs.dats, case_type: :priority, lsb_first: rhs.lsb_first)
        @stmts << stmt
        @last_if = nil
        return stmt
      end

      if RSV.contains_instance_port?(lhs) || RSV.contains_instance_port?(rhs)
        raise ArgumentError, "instance ports cannot be assigned inside procedural blocks"
      end

      normalized_lhs = RSV.normalize_expr(lhs)
      normalized_rhs = RSV.normalize_expr(rhs)

      stmt = if @assign_context == :always_ff
        NbAssign.new(normalized_lhs, normalized_rhs)
      else
        BlockingAssign.new(normalized_lhs, normalized_rhs)
      end

      @stmts << stmt
      @last_if = nil
      stmt
    end
  end

  # Builder for case/casez/casex blocks — used inside svcase/svcasez/svcasex.
  class CaseBuilder
    def initialize(assign_context, expr, case_kind:, qualifier: nil)
      @assign_context = assign_context
      @stmt = CaseStmt.new(expr, case_kind: case_kind, qualifier: qualifier)
    end

    def build(&block)
      instance_eval(&block) if block_given?
    end

    def to_stmt
      @stmt
    end

    # is(val1, val2, ...) { ... } — a case branch
    def is(*vals, &block)
      builder = ProceduralBuilder.new(assign_context: @assign_context)
      builder.build(&block)
      normalized_vals = vals.map { |v| RSV.normalize_expr(v) }
      @stmt.add_branch(normalized_vals, builder.stmts)
    end

    # fallin { ... } — the default branch
    def fallin(&block)
      builder = ProceduralBuilder.new(assign_context: @assign_context)
      builder.build(&block)
      @stmt.set_default(builder.stmts)
    end
  end

  # Chainable wrapper returned by svif/svelif — allows compact if/elsif/else chains.
  class IfChain
    def initialize(proc_builder, if_stmt)
      @proc_builder = proc_builder
      @if_stmt = if_stmt
    end

    def svelif(cond, &block)
      @proc_builder.svelif(cond, &block)
    end

    def svelse(&block)
      @proc_builder.svelse(&block)
    end
  end
end
