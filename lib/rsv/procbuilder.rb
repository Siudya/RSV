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
    def svif(cond, unique: false, priority: false, &block)
      qual = unique ? :unique : (priority ? :priority : nil)
      builder = ProceduralBuilder.new(assign_context: @assign_context)
      builder.build(&block)
      stmt    = IfStmt.new(RSV.normalize_expr(cond), builder.stmts, qualifier: qual)
      @stmts << stmt
      @last_if = stmt
      IfChain.new(self, stmt)
    end

    # else if (<cond>) begin ... end  — must follow svif or svelif
    def svelif(cond, &block)
      raise "svelif called without a preceding svif" unless @last_if

      builder = ProceduralBuilder.new(assign_context: @assign_context)
      builder.build(&block)
      @last_if.add_elsif(RSV.normalize_expr(cond), builder.stmts)
      IfChain.new(self, @last_if)
    end

    # else begin ... end  — must follow svif or svelif
    def svelse(&block)
      raise "svelse called without a preceding svif" unless @last_if

      builder = ProceduralBuilder.new(assign_context: @assign_context)
      builder.build(&block)
      @last_if.set_else(builder.stmts)
      @last_if = nil
    end

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

    def pop_count(vec)
      PopCountExpr.new(vec)
    end

    def log2ceil(n)
      RSV.log2ceil(n)
    end

    def sv_dref(name)
      MacroRef.new(name.to_s)
    end

    def sv_plugin(code)
      @stmts << SvPlugin.new(code.to_s)
    end

    private

    def append_assignment(lhs, rhs)
      # Expand mux1h/muxp/pop_count via module-level temp wire + always_comb
      if rhs.is_a?(Mux1hExpr) || rhs.is_a?(MuxpExpr) || rhs.is_a?(PopCountExpr)
        mod = RSV.current_module_def
        raise ArgumentError, "mux1h/muxp/pop_count requires a module context" unless mod
        rhs = mod.send(:expand_complex_rhs, rhs)
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
