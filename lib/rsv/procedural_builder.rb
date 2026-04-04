# frozen_string_literal: true

module RSV
  # Builder used inside always_ff and always_comb blocks.
  # Provides nb_assign, assign, if_stmt, elsif_stmt, else_stmt.
  class ProceduralBuilder
    attr_reader :stmts

    def initialize
      @stmts    = []
      @last_if  = nil
    end

    # Non-blocking assignment:  lhs <= rhs;
    def nb_assign(lhs, rhs)
      @stmts   << NbAssign.new(lhs, rhs)
      @last_if  = nil
    end

    # Blocking assignment:  lhs = rhs;
    def assign(lhs, rhs)
      @stmts   << BlockingAssign.new(lhs, rhs)
      @last_if  = nil
    end

    # if (<cond>) begin ... end
    def if_stmt(cond, &block)
      builder = ProceduralBuilder.new
      builder.instance_eval(&block) if block_given?
      stmt     = IfStmt.new(cond, builder.stmts)
      @stmts  << stmt
      @last_if = stmt
    end

    # else if (<cond>) begin ... end  — must follow if_stmt or elsif_stmt
    def elsif_stmt(cond, &block)
      raise "elsif_stmt called without a preceding if_stmt" unless @last_if

      builder = ProceduralBuilder.new
      builder.instance_eval(&block) if block_given?
      @last_if.add_elsif(cond, builder.stmts)
    end

    # else begin ... end  — must follow if_stmt or elsif_stmt
    def else_stmt(&block)
      raise "else_stmt called without a preceding if_stmt" unless @last_if

      builder = ProceduralBuilder.new
      builder.instance_eval(&block) if block_given?
      @last_if.set_else(builder.stmts)
      @last_if = nil
    end
  end
end
