# frozen_string_literal: true

module RSV
  # Lowers the Ruby-friendly AST into an emitter-friendly IR:
  # - converts reg declarations to logic declarations
  # - inserts implicit reset branches for domain-driven always_ff blocks
  # - sizes numeric literals from surrounding context
  class Elaborator
    def elaborate(mod)
      @source_locals_by_name = mod.locals.each_with_object({}) { |local, memo| memo[local.name] = local }

      ElaboratedModule.new(
        mod.name,
        params: mod.params.dup,
        ports: mod.ports.dup,
        locals: mod.locals.map { |local| elaborate_local(local) },
        stmts: mod.stmts.flat_map { |stmt| elaborate_stmt(stmt) }
      )
    end

    private

    def elaborate_local(local)
      spec = SignalSpec.new(
        local.name,
        width: local.width,
        signed: local.signed,
        init: local.init,
        packed_dims: local.packed_dims,
        unpacked_dims: local.unpacked_dims
      )
      return ConstDecl.new(spec, init: local.init, attr: local.attr) if local.is_a?(ConstDecl)

      LocalDecl.new(local.sv_kind, spec, init: local.init, reset_init: local.reset_init, attr: local.attr)
    end

    def elaborate_stmt(stmt)
      case stmt
      when AssignStmt
        [AssignStmt.new(elaborate_expr(stmt.lhs), elaborate_expr(stmt.rhs, target_width: RSV.infer_expr_width(stmt.lhs)))]
      when AlwaysFF
        [elaborate_always_ff(stmt)]
      when AlwaysLatch
        [AlwaysLatch.new(stmt.body.map { |proc_stmt| elaborate_proc_stmt(proc_stmt) })]
      when AlwaysComb
        [AlwaysComb.new(stmt.body.map { |proc_stmt| elaborate_proc_stmt(proc_stmt) })]
      when Instance
        [Instance.new(stmt.module_name, stmt.inst_name, params: stmt.params, connections: elaborate_connections(stmt.connections))]
      else
        [stmt]
      end
    end

    def elaborate_connections(connections)
      connections.transform_values { |signal| elaborate_expr(signal) }
    end

    def elaborate_always_ff(stmt)
      body = stmt.body.map { |proc_stmt| elaborate_proc_stmt(proc_stmt) }

      if stmt.domain_driven?
        clk = stmt.clock
        rst = stmt.reset

        clk_edge = clk.is_a?(ClockSignal) && clk.negated ? "negedge" : "posedge"
        rst_edge = rst.is_a?(ResetSignal) && rst.negated ? "negedge" : "posedge"
        clk_name = clk.is_a?(ClockSignal) ? clk.name : clk.to_s
        rst_name = rst.is_a?(ResetSignal) ? rst.name : rst.to_s

        if rst.is_a?(ResetSignal) && rst.negated
          reset_expr = elaborate_expr(UnaryExpr.new(:!, RSV.normalize_expr(rst_name)))
        else
          reset_expr = elaborate_expr(RSV.normalize_expr(rst_name))
        end

        body = synthesize_reset_body(reset_expr, body)
        sensitivity = "#{clk_edge} #{clk_name} or #{rst_edge} #{rst_name}"
      else
        sensitivity = stmt.sensitivity
      end

      AlwaysFF.new(body, sensitivity: sensitivity)
    end

    def synthesize_reset_body(reset_expr, body)
      assigned_names = collect_assigned_names(body)
      reset_locals = assigned_names.filter_map do |name|
        local = @source_locals_by_name[name]
        local if local&.resettable?
      end
      return body if reset_locals.empty?

      reset_body = reset_locals.flat_map { |local| synthesize_local_reset(local) }

      reset_stmt = IfStmt.new(reset_expr, reset_body)

      if body.size == 1 && body.first.is_a?(IfStmt)
        merge_reset_with_if(reset_stmt, body.first)
        [reset_stmt]
      else
        reset_stmt.set_else(body)
        [reset_stmt]
      end
    end

    def merge_reset_with_if(reset_stmt, if_stmt)
      reset_stmt.add_elsif(if_stmt.cond, if_stmt.then_stmts)
      if_stmt.elsif_clauses.each do |clause|
        reset_stmt.add_elsif(clause[:cond], clause[:stmts])
      end
      reset_stmt.set_else(if_stmt.else_stmts) if if_stmt.else_stmts
    end

    def synthesize_local_reset(local)
      lhs = SignalHandler.new(
        local.name,
        width: local.width,
        signed: local.signed,
        kind: :logic,
        packed_dims: local.packed_dims,
        unpacked_dims: local.unpacked_dims
      )
      rhs = elaborate_expr(RSV.reset_init_expr(local.reset_init, local.width), target_width: local.width)
      dims = local.unpacked_dims + local.packed_dims
      build_reset_loop(lhs, dims, rhs, local.name, 0)
    end

    def build_reset_loop(lhs, dims, rhs, base_name, depth)
      return [NbAssign.new(lhs, rhs)] if dims.empty?

      idx_name = "#{base_name}_idx_#{depth}"
      indexed_lhs = IndexExpr.new(lhs, RawExpr.new(idx_name))
      limit = elaborate_expr(dims.first)
      body = build_reset_loop(indexed_lhs, dims.drop(1), rhs, base_name, depth + 1)
      [ForStmt.new(idx_name, limit, body)]
    end

    def collect_assigned_names(stmts)
      names = []
      stmts.each { |stmt| collect_assigned_names_from_stmt(stmt, names) }
      names.uniq
    end

    def collect_assigned_names_from_stmt(stmt, names)
      case stmt
      when NbAssign, BlockingAssign
        names << stmt.lhs.base_name if stmt.lhs.respond_to?(:base_name)
      when IfStmt
        stmt.then_stmts.each { |nested| collect_assigned_names_from_stmt(nested, names) }
        stmt.elsif_clauses.each do |clause|
          clause[:stmts].each { |nested| collect_assigned_names_from_stmt(nested, names) }
        end
        stmt.else_stmts&.each { |nested| collect_assigned_names_from_stmt(nested, names) }
      end
    end

    def elaborate_proc_stmt(stmt)
      case stmt
      when NbAssign
        lhs = elaborate_expr(stmt.lhs)
        NbAssign.new(lhs, elaborate_expr(stmt.rhs, target_width: RSV.infer_expr_width(lhs)))
      when BlockingAssign
        lhs = elaborate_expr(stmt.lhs)
        BlockingAssign.new(lhs, elaborate_expr(stmt.rhs, target_width: RSV.infer_expr_width(lhs)))
      when IfStmt
        lowered = IfStmt.new(elaborate_expr(stmt.cond), stmt.then_stmts.map { |nested| elaborate_proc_stmt(nested) })
        stmt.elsif_clauses.each do |clause|
          lowered.add_elsif(elaborate_expr(clause[:cond]), clause[:stmts].map { |nested| elaborate_proc_stmt(nested) })
        end
        lowered.set_else(stmt.else_stmts.map { |nested| elaborate_proc_stmt(nested) }) if stmt.else_stmts
        lowered
      else
        stmt
      end
    end

    def elaborate_expr(expr, target_width: nil)
      expr = RSV.normalize_expr(expr)

      case expr
      when SignalHandler, ClockSignal, ResetSignal
        expr
      when RawExpr
        expr
      when LiteralExpr
        target_width ? expr.with_width(target_width) : expr
      when UnaryExpr
        elaborate_unary_expr(expr, target_width: target_width)
      when ParenExpr
        ParenExpr.new(elaborate_expr(expr.inner, target_width: target_width))
      when IndexExpr
        IndexExpr.new(elaborate_expr(expr.base), elaborate_expr(expr.index))
      when RangeSelectExpr
        RangeSelectExpr.new(elaborate_expr(expr.base), elaborate_expr(expr.msb), elaborate_expr(expr.lsb))
      when IndexedPartSelectExpr
        IndexedPartSelectExpr.new(elaborate_expr(expr.base), elaborate_expr(expr.start), expr.direction, elaborate_expr(expr.part_width))
      when BinaryExpr
        elaborate_binary_expr(expr, target_width: target_width)
      when AsSintExpr
        AsSintExpr.new(elaborate_expr(expr.operand, target_width: target_width))
      when MuxExpr
        MuxExpr.new(elaborate_expr(expr.sel), elaborate_expr(expr.a, target_width: target_width), elaborate_expr(expr.b, target_width: target_width))
      when CatExpr
        CatExpr.new(expr.parts.map { |p| elaborate_expr(p) })
      when FillExpr
        FillExpr.new(elaborate_expr(expr.count), elaborate_expr(expr.part))
      when PackedCollectionExpr
        PackedCollectionExpr.new(
          expr.parts_low_to_high.map { |part| elaborate_expr(part) },
          width: expr.width,
          signed: expr.signed,
          packed_dims: expr.packed_dims,
          unpacked_dims: expr.unpacked_dims
        )
      else
        expr
      end
    end

    def elaborate_binary_expr(expr, target_width:)
      lhs_width = RSV.infer_expr_width(expr.lhs)
      rhs_width = RSV.infer_expr_width(expr.rhs)
      shared_width = [lhs_width, rhs_width].compact.max || target_width

      lhs = elaborate_expr(expr.lhs, target_width: literal_target_width(expr.op, expr.lhs, rhs_width, shared_width))
      rhs = elaborate_expr(expr.rhs, target_width: literal_target_width(expr.op, expr.rhs, lhs_width, shared_width))
      BinaryExpr.new(lhs, expr.op, rhs)
    end

    def elaborate_unary_expr(expr, target_width:)
      operand_target = unary_literal_target_width(expr.op, target_width)
      UnaryExpr.new(expr.op, elaborate_expr(expr.operand, target_width: operand_target))
    end

    def literal_target_width(op, expr, other_width, fallback_width)
      return nil unless expr.is_a?(LiteralExpr)

      case op
      when :<, :<=, :>, :>=, :==, :!=, :logic_and, :logic_or, :+, :-, :*, :/, :%, :<<, :>>, :&, :|, :^
        other_width || fallback_width
      else
        fallback_width
      end
    end

    def unary_literal_target_width(op, fallback_width)
      case op
      when :~
        fallback_width
      else
        nil
      end
    end
  end
end
