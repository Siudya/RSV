# frozen_string_literal: true

module RSV
  class AssignmentValidator
    REG_ASSIGN_CONTEXTS = [:always_ff, :always_latch].freeze
    WIRE_ASSIGN_CONTEXTS = [:assign, :always_comb].freeze
    SIMPLE_LHS_PATTERN = /\A([A-Za-z_][A-Za-z0-9_]*)\s*(?:\[[^\]]+\])?\z/

    def validate(mod)
      @locals_by_name = mod.locals.each_with_object({}) { |local, memo| memo[local.name] = local }
      @ports_by_name = mod.ports.each_with_object({}) { |port, memo| memo[port.name] = port }
      @driver_contexts_by_name = {}
      mod.stmts.each_with_index { |stmt, idx| validate_stmt(stmt, driver_context: driver_context_for(stmt, idx)) }
    end

    private

    def validate_stmt(stmt, driver_context:)
      case stmt
      when AssignStmt
        validate_assignment_target(stmt.lhs, context: :assign, driver_context: driver_context)
      when AlwaysFF
        validate_proc_stmts(stmt.body, context: :always_ff, driver_context: driver_context)
      when AlwaysLatch
        validate_proc_stmts(stmt.body, context: :always_latch, driver_context: driver_context)
      when AlwaysComb
        validate_proc_stmts(stmt.body, context: :always_comb, driver_context: driver_context)
      when SvIfdef, SvIfndef
        validate_macro_cond(stmt, driver_context: driver_context)
      end
    end

    def validate_proc_stmts(stmts, context:, driver_context:)
      stmts.each { |stmt| validate_proc_stmt(stmt, context: context, driver_context: driver_context) }
    end

    def validate_proc_stmt(stmt, context:, driver_context:)
      case stmt
      when NbAssign, BlockingAssign
        validate_assignment_target(stmt.lhs, context: context, driver_context: driver_context)
      when IfStmt
        validate_proc_stmts(stmt.then_stmts, context: context, driver_context: driver_context)
        stmt.elsif_clauses.each do |clause|
          validate_proc_stmts(clause[:stmts], context: context, driver_context: driver_context)
        end
        validate_proc_stmts(stmt.else_stmts, context: context, driver_context: driver_context) if stmt.else_stmts
      when MuxCaseStmt
        validate_assignment_target(stmt.lhs, context: context, driver_context: driver_context)
      end
    end

    def validate_assignment_target(lhs, context:, driver_context:)
      signal = resolve_assigned_signal(lhs)
      return unless signal

      raise ArgumentError, "const signal #{signal.name} cannot be assigned" if signal.is_a?(ConstDecl)
      validate_local_assignment_context(signal, context) if signal.is_a?(LocalDecl)
      validate_driver_context(signal.name, driver_context)
    end

    def resolve_assigned_signal(lhs)
      name = assigned_base_name(lhs)
      return unless name

      @locals_by_name[name] || @ports_by_name[name]
    end

    def validate_local_assignment_context(local, context)
      case local.kind
      when :reg
        return if REG_ASSIGN_CONTEXTS.include?(context)

        raise ArgumentError, "reg signal #{local.name} must be assigned inside always_ff or always_latch"
      when :wire
        return if WIRE_ASSIGN_CONTEXTS.include?(context)

        raise ArgumentError, "wire signal #{local.name} must be assigned inside always_comb or outside procedural blocks"
      end
    end

    def validate_driver_context(name, driver_context)
      existing = @driver_contexts_by_name[name]
      if existing && existing != driver_context
        raise ArgumentError, "signal #{name} cannot be assigned in multiple always/assign blocks"
      end

      @driver_contexts_by_name[name] = driver_context
    end

    def assigned_base_name(lhs)
      expr = RSV.normalize_expr(lhs)

      case expr
      when ClockSignal, ResetSignal
        expr.name
      when SignalHandler, IndexExpr, RangeSelectExpr, IndexedPartSelectExpr
        expr.base_name
      when RawExpr
        raw_expr_base_name(expr.source)
      else
        nil
      end
    end

    def raw_expr_base_name(source)
      match = source.match(SIMPLE_LHS_PATTERN)
      match && match[1]
    end

    def driver_context_for(stmt, idx)
      "#{stmt.class.name}:#{idx}"
    end

    def validate_macro_cond(stmt, driver_context:)
      stmt.body.each_with_index { |s, idx| validate_stmt(s, driver_context: driver_context_for(s, idx)) }
      stmt.elsif_clauses.each { |clause| clause[:body].each_with_index { |s, idx| validate_stmt(s, driver_context: driver_context_for(s, idx)) } }
      stmt.else_body&.each_with_index { |s, idx| validate_stmt(s, driver_context: driver_context_for(s, idx)) }
    end
  end
end
