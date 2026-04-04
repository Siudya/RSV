# frozen_string_literal: true

module RSV
  # Converts a ModuleDef AST into a formatted SystemVerilog string.
  # The output aims to be close to idiomatic, hand-written SV:
  #   - port directions and types are column-aligned
  #   - proper indentation throughout
  #   - blank lines between declaration sections and statements
  class Emitter
    INDENT = "  "

    # Emit a complete module as a String.
    def emit_module(mod)
      lines = []

      # ── Module header ──────────────────────────────────────────────────────
      if mod.params.empty?
        lines << "module #{mod.name} ("
      else
        lines << "module #{mod.name} #("
        lines.concat(emit_params_list(mod.params))
        lines << ") ("
      end

      lines.concat(emit_ports_list(mod.ports))
      lines << ");"
      lines << ""

      # ── Local signal declarations ──────────────────────────────────────────
      unless mod.locals.empty?
        mod.locals.each { |sig| lines << emit_logic_decl(sig, 1) }
        lines << ""
      end

      # ── Statements ─────────────────────────────────────────────────────────
      mod.stmts.each_with_index do |stmt, idx|
        lines.concat(emit_stmt(stmt, 1))
        lines << "" if idx < mod.stmts.size - 1
      end

      lines << "" unless mod.stmts.empty?
      lines << "endmodule"

      lines.join("\n")
    end

    private

    # ── Helpers ───────────────────────────────────────────────────────────────

    def ind(level)
      INDENT * level
    end

    # Returns a packed-dimension string such as "[7:0]", "[WIDTH-1:0]", or nil
    # for single-bit signals.
    def packed_dim(width)
      return nil if width == 1 || width == "1"

      if width.is_a?(Integer)
        "[#{width - 1}:0]"
      else
        "[#{width}-1:0]"
      end
    end

    # ── Parameter list ────────────────────────────────────────────────────────

    def emit_params_list(params)
      params.each_with_index.map do |p, idx|
        comma     = idx < params.size - 1 ? "," : ""
        type_part = p.param_type ? "#{p.param_type} " : ""
        "#{ind(1)}parameter #{type_part}#{p.name} = #{p.value}#{comma}"
      end
    end

    # ── Port list ─────────────────────────────────────────────────────────────

    def emit_ports_list(ports)
      return [] if ports.empty?

      # Build intermediate entries to compute alignment widths.
      entries = ports.map do |p|
        dim        = packed_dim(p.width)
        signed_str = p.signed ? "signed " : ""
        type_part  = "logic #{signed_str}#{dim ? "#{dim} " : ""}"
        { dir: p.dir.to_s, type: type_part, name: p.name }
      end

      max_dir  = entries.map { |e| e[:dir].length  }.max
      max_type = entries.map { |e| e[:type].length }.max

      entries.each_with_index.map do |e, idx|
        comma = idx < entries.size - 1 ? "," : ""
        dir   = e[:dir].ljust(max_dir)
        type  = e[:type].ljust(max_type)
        "#{ind(1)}#{dir} #{type}#{e[:name]}#{comma}"
      end
    end

    # ── Logic declaration ─────────────────────────────────────────────────────

    def emit_logic_decl(sig, level)
      dim        = packed_dim(sig.width)
      signed_str = sig.signed ? "signed " : ""
      type_part  = "logic #{signed_str}#{dim ? "#{dim} " : ""}"
      "#{ind(level)}#{type_part}#{sig.name};"
    end

    # ── Top-level statements ──────────────────────────────────────────────────

    def emit_stmt(stmt, level)
      case stmt
      when AssignStmt
        ["#{ind(level)}assign #{stmt.lhs} = #{stmt.rhs};"]
      when AlwaysFF
        emit_always_ff(stmt, level)
      when AlwaysComb
        emit_always_comb(stmt, level)
      when Instance
        emit_instance(stmt, level)
      else
        ["#{ind(level)}// unknown statement: #{stmt.class}"]
      end
    end

    # ── always_ff ─────────────────────────────────────────────────────────────

    def emit_always_ff(stmt, level)
      lines = ["#{ind(level)}always_ff @(#{stmt.sensitivity}) begin"]
      stmt.body.each { |s| lines.concat(emit_proc_stmt(s, level + 1)) }
      lines << "#{ind(level)}end"
    end

    # ── always_comb ───────────────────────────────────────────────────────────

    def emit_always_comb(stmt, level)
      lines = ["#{ind(level)}always_comb begin"]
      stmt.body.each { |s| lines.concat(emit_proc_stmt(s, level + 1)) }
      lines << "#{ind(level)}end"
    end

    # ── Procedural statements ─────────────────────────────────────────────────

    def emit_proc_stmt(stmt, level)
      case stmt
      when NbAssign
        ["#{ind(level)}#{stmt.lhs} <= #{stmt.rhs};"]
      when BlockingAssign
        ["#{ind(level)}#{stmt.lhs} = #{stmt.rhs};"]
      when IfStmt
        emit_if_stmt(stmt, level)
      else
        ["#{ind(level)}// unknown proc stmt: #{stmt.class}"]
      end
    end

    def emit_if_stmt(stmt, level)
      lines = ["#{ind(level)}if (#{stmt.cond}) begin"]
      stmt.then_stmts.each { |s| lines.concat(emit_proc_stmt(s, level + 1)) }

      stmt.elsif_clauses.each do |clause|
        lines << "#{ind(level)}end else if (#{clause[:cond]}) begin"
        clause[:stmts].each { |s| lines.concat(emit_proc_stmt(s, level + 1)) }
      end

      if stmt.else_stmts
        lines << "#{ind(level)}end else begin"
        stmt.else_stmts.each { |s| lines.concat(emit_proc_stmt(s, level + 1)) }
      end

      lines << "#{ind(level)}end"
    end

    # ── Module instantiation ──────────────────────────────────────────────────

    def emit_instance(inst, level)
      lines = []

      if inst.params.empty?
        lines << "#{ind(level)}#{inst.module_name} #{inst.inst_name} ("
      else
        lines << "#{ind(level)}#{inst.module_name} #("
        param_pairs = inst.params.to_a
        param_pairs.each_with_index do |(k, v), idx|
          comma = idx < param_pairs.size - 1 ? "," : ""
          lines << "#{ind(level + 1)}.#{k}(#{v})#{comma}"
        end
        lines << "#{ind(level)}) #{inst.inst_name} ("
      end

      conn_pairs = inst.connections.to_a
      conn_pairs.each_with_index do |(port, sig), idx|
        comma = idx < conn_pairs.size - 1 ? "," : ""
        lines << "#{ind(level + 1)}.#{port}(#{sig})#{comma}"
      end

      lines << "#{ind(level)});"
    end
  end
end
