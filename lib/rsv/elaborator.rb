# frozen_string_literal: true

module RSV
  # Lowers the Ruby-friendly AST into an emitter-friendly IR:
  # - converts reg declarations to logic declarations
  # - inserts implicit reset branches for domain-driven always_ff blocks
  # - sizes numeric literals from surrounding context
  class Elaborator
    def elaborate(mod)
      @sourceLocalsByName = mod.locals.each_with_object({}) { |local, memo| memo[local.name] = local }

      ElaboratedModule.new(
        mod.name,
        params: mod.params.dup,
        ports: mod.ports.dup,
        locals: mod.locals.map { |local| elaborateLocal(local) },
        stmts: mod.stmts.flat_map { |stmt| elaborateStmt(stmt) }
      )
    end

    private

    def elaborateLocal(local)
      spec = SignalSpec.new(local.name, width: local.width, signed: local.signed, init: local.init)
      LocalDecl.new(local.svKind, spec, init: local.init, resetInit: local.resetInit)
    end

    def elaborateStmt(stmt)
      case stmt
      when AssignStmt
        [AssignStmt.new(elaborateExpr(stmt.lhs), elaborateExpr(stmt.rhs, targetWidth: RSV.inferExprWidth(stmt.lhs)))]
      when AlwaysFF
        [elaborateAlwaysFf(stmt)]
      when AlwaysLatch
        [AlwaysLatch.new(stmt.body.map { |procStmt| elaborateProcStmt(procStmt) })]
      when AlwaysComb
        [AlwaysComb.new(stmt.body.map { |procStmt| elaborateProcStmt(procStmt) })]
      when Instance
        [Instance.new(stmt.moduleName, stmt.instName, params: stmt.params, connections: elaborateConnections(stmt.connections))]
      else
        [stmt]
      end
    end

    def elaborateConnections(connections)
      connections.transform_values { |signal| elaborateExpr(signal) }
    end

    def elaborateAlwaysFf(stmt)
      body = stmt.body.map { |procStmt| elaborateProcStmt(procStmt) }

      if stmt.domainDriven?
        resetExpr = elaborateExpr(stmt.reset)
        body = synthesizeResetBody(resetExpr, body)
        sensitivity = "posedge #{stmt.clock} or posedge #{stmt.reset}"
      else
        sensitivity = stmt.sensitivity
      end

      AlwaysFF.new(body, sensitivity: sensitivity)
    end

    def synthesizeResetBody(resetExpr, body)
      assignedNames = collectAssignedNames(body)
      resetLocals = assignedNames.filter_map do |name|
        local = @sourceLocalsByName[name]
        local if local&.resettable?
      end
      return body if resetLocals.empty?

      resetBody = resetLocals.map do |local|
        lhs = SignalHandler.new(local.name, width: local.width, signed: local.signed, kind: :logic)
        rhs = elaborateExpr(RSV.resetInitExpr(local.resetInit, local.width), targetWidth: local.width)
        NbAssign.new(lhs, rhs)
      end

      resetStmt = IfStmt.new(resetExpr, resetBody)

      if body.size == 1 && body.first.is_a?(IfStmt)
        mergeResetWithIf(resetStmt, body.first)
        [resetStmt]
      else
        resetStmt.setElse(body)
        [resetStmt]
      end
    end

    def mergeResetWithIf(resetStmt, ifStmt)
      resetStmt.addElsif(ifStmt.cond, ifStmt.thenStmts)
      ifStmt.elsifClauses.each do |clause|
        resetStmt.addElsif(clause[:cond], clause[:stmts])
      end
      resetStmt.setElse(ifStmt.elseStmts) if ifStmt.elseStmts
    end

    def collectAssignedNames(stmts)
      names = []
      stmts.each { |stmt| collectAssignedNamesFromStmt(stmt, names) }
      names.uniq
    end

    def collectAssignedNamesFromStmt(stmt, names)
      case stmt
      when NbAssign, BlockingAssign
        names << stmt.lhs.baseName if stmt.lhs.respond_to?(:baseName)
      when IfStmt
        stmt.thenStmts.each { |nested| collectAssignedNamesFromStmt(nested, names) }
        stmt.elsifClauses.each do |clause|
          clause[:stmts].each { |nested| collectAssignedNamesFromStmt(nested, names) }
        end
        stmt.elseStmts&.each { |nested| collectAssignedNamesFromStmt(nested, names) }
      end
    end

    def elaborateProcStmt(stmt)
      case stmt
      when NbAssign
        lhs = elaborateExpr(stmt.lhs)
        NbAssign.new(lhs, elaborateExpr(stmt.rhs, targetWidth: RSV.inferExprWidth(lhs)))
      when BlockingAssign
        lhs = elaborateExpr(stmt.lhs)
        BlockingAssign.new(lhs, elaborateExpr(stmt.rhs, targetWidth: RSV.inferExprWidth(lhs)))
      when IfStmt
        lowered = IfStmt.new(elaborateExpr(stmt.cond), stmt.thenStmts.map { |nested| elaborateProcStmt(nested) })
        stmt.elsifClauses.each do |clause|
          lowered.addElsif(elaborateExpr(clause[:cond]), clause[:stmts].map { |nested| elaborateProcStmt(nested) })
        end
        lowered.setElse(stmt.elseStmts.map { |nested| elaborateProcStmt(nested) }) if stmt.elseStmts
        lowered
      else
        stmt
      end
    end

    def elaborateExpr(expr, targetWidth: nil)
      expr = RSV.normalizeExpr(expr)

      case expr
      when SignalHandler
        expr
      when RawExpr
        expr
      when LiteralExpr
        targetWidth ? expr.withWidth(targetWidth) : expr
      when IndexExpr
        IndexExpr.new(elaborateExpr(expr.base), elaborateExpr(expr.index))
      when BinaryExpr
        elaborateBinaryExpr(expr, targetWidth: targetWidth)
      else
        expr
      end
    end

    def elaborateBinaryExpr(expr, targetWidth:)
      lhsWidth = RSV.inferExprWidth(expr.lhs)
      rhsWidth = RSV.inferExprWidth(expr.rhs)
      sharedWidth = [lhsWidth, rhsWidth].compact.max || targetWidth

      lhs = elaborateExpr(expr.lhs, targetWidth: literalTargetWidth(expr.op, expr.lhs, rhsWidth, sharedWidth))
      rhs = elaborateExpr(expr.rhs, targetWidth: literalTargetWidth(expr.op, expr.rhs, lhsWidth, sharedWidth))
      BinaryExpr.new(lhs, expr.op, rhs)
    end

    def literalTargetWidth(op, expr, otherWidth, fallbackWidth)
      return nil unless expr.is_a?(LiteralExpr)

      case op
      when :<, :>, :>=, :+, :-, :&, :|, :^
        otherWidth || fallbackWidth
      else
        fallbackWidth
      end
    end
  end
end
