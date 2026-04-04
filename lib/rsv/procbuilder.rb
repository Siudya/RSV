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

    private

    def append_assignment(lhs, rhs)
      raise ArgumentError, "instance ports cannot be assigned inside procedural blocks" if lhs.is_a?(InstancePortHandler) || rhs.is_a?(InstancePortHandler)

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
