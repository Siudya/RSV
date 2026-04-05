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
    def if_stmt(cond, &block)
      builder = ProceduralBuilder.new(assign_context: @assign_context)
      builder.build(&block)
      stmt    = IfStmt.new(RSV.normalize_expr(cond), builder.stmts)
      @stmts << stmt
      @last_if = stmt
    end

    def svif(cond, &block)
      if_stmt(cond, &block)
    end

    # else if (<cond>) begin ... end  — must follow if_stmt or elsif_stmt
    def elsif_stmt(cond, &block)
      raise "elsif_stmt called without a preceding if_stmt" unless @last_if

      builder = ProceduralBuilder.new(assign_context: @assign_context)
      builder.build(&block)
      @last_if.add_elsif(RSV.normalize_expr(cond), builder.stmts)
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

    def cat(*parts)
      CatExpr.new(parts)
    end

    def fill(n, part)
      FillExpr.new(n, part)
    end

    def mux1h(sel1h, dats, result:)
      raise ArgumentError, "mux1h sel must be a wire(uint) handler" unless sel1h.is_a?(SignalHandler)
      raise ArgumentError, "mux1h result must be assignable" unless result.is_a?(SignalHandler)

      @stmts << MuxCaseStmt.new(result, sel1h, dats, case_type: :unique)
      @last_if = nil
      result
    end

    def muxp(sel, dats, result:, lsb_first: true)
      raise ArgumentError, "muxp sel must be a wire(uint) handler" unless sel.is_a?(SignalHandler)
      raise ArgumentError, "muxp result must be assignable" unless result.is_a?(SignalHandler)

      @stmts << MuxCaseStmt.new(result, sel, dats, case_type: :priority, lsb_first: lsb_first)
      @last_if = nil
      result
    end

    private

    def append_assignment(lhs, rhs)
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
end
