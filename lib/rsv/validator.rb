# frozen_string_literal: true

module RSV
  class AssignmentValidator
    REG_ASSIGN_CONTEXTS = [:always_ff, :always_latch].freeze
    SIMPLE_LHS_PATTERN = /\A([A-Za-z_][A-Za-z0-9_]*)\s*(?:\[[^\]]+\])?\z/

    def validate(mod)
      @localsByName = mod.locals.each_with_object({}) { |local, memo| memo[local.name] = local }
      mod.stmts.each { |stmt| validateStmt(stmt) }
    end

    private

    def validateStmt(stmt)
      case stmt
      when AssignStmt
        validateAssignmentTarget(stmt.lhs, context: :assign)
      when AlwaysFF
        validateProcStmts(stmt.body, context: :always_ff)
      when AlwaysLatch
        validateProcStmts(stmt.body, context: :always_latch)
      when AlwaysComb
        validateProcStmts(stmt.body, context: :always_comb)
      end
    end

    def validateProcStmts(stmts, context:)
      stmts.each { |stmt| validateProcStmt(stmt, context: context) }
    end

    def validateProcStmt(stmt, context:)
      case stmt
      when NbAssign, BlockingAssign
        validateAssignmentTarget(stmt.lhs, context: context)
      when IfStmt
        validateProcStmts(stmt.thenStmts, context: context)
        stmt.elsifClauses.each do |clause|
          validateProcStmts(clause[:stmts], context: context)
        end
        validateProcStmts(stmt.elseStmts, context: context) if stmt.elseStmts
      end
    end

    def validateAssignmentTarget(lhs, context:)
      local = resolveAssignedLocal(lhs)
      return unless local
      return unless local.kind == :reg
      return if REG_ASSIGN_CONTEXTS.include?(context)

      raise ArgumentError, "reg signal #{local.name} must be assigned inside always_ff or always_latch"
    end

    def resolveAssignedLocal(lhs)
      name = assignedBaseName(lhs)
      return unless name

      @localsByName[name]
    end

    def assignedBaseName(lhs)
      expr = RSV.normalizeExpr(lhs)

      case expr
      when SignalHandler
        expr.baseName
      when IndexExpr
        assignedBaseName(expr.base)
      when RawExpr
        rawExprBaseName(expr.source)
      else
        nil
      end
    end

    def rawExprBaseName(source)
      match = source.match(SIMPLE_LHS_PATTERN)
      match && match[1]
    end
  end
end
