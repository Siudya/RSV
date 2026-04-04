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
    def emitModule(mod)
      lines = []

      # ── Module header ──────────────────────────────────────────────────────
      if mod.params.empty?
        lines << "module #{mod.name} ("
      else
        lines << "module #{mod.name} #("
        lines.concat(emitParamsList(mod.params))
        lines << ") ("
      end

      lines.concat(emitPortsList(mod.ports))
      lines << ");"
      lines << ""

      # ── Local signal declarations ──────────────────────────────────────────
      unless mod.locals.empty?
        mod.locals.each { |sig| lines << emitLogicDecl(sig, 1) }
        lines << ""
      end

      # ── Statements ─────────────────────────────────────────────────────────
      mod.stmts.each_with_index do |stmt, idx|
        lines.concat(emitStmt(stmt, 1))
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
    def packedDim(width)
      return nil if width == 1 || width == "1"

      if width.is_a?(Integer)
        "[#{width - 1}:0]"
      else
        "[#{width}-1:0]"
      end
    end

    # ── Parameter list ────────────────────────────────────────────────────────

    def emitParamsList(params)
      params.each_with_index.map do |p, idx|
        comma    = idx < params.size - 1 ? "," : ""
        typePart = p.paramType ? "#{p.paramType} " : ""
        "#{ind(1)}parameter #{typePart}#{p.name} = #{p.value}#{comma}"
      end
    end

    # ── Port list ─────────────────────────────────────────────────────────────

    def emitPortsList(ports)
      return [] if ports.empty?

      # Build intermediate entries to compute alignment widths.
      entries = ports.map do |p|
        dim       = packedDim(p.width)
        signedStr = p.signed ? "signed " : ""
        typePart  = "logic #{signedStr}#{dim ? "#{dim} " : ""}"
        { dir: p.dir.to_s, type: typePart, name: p.name }
      end

      maxDir  = entries.map { |e| e[:dir].length  }.max
      maxType = entries.map { |e| e[:type].length }.max

      entries.each_with_index.map do |e, idx|
        comma = idx < entries.size - 1 ? "," : ""
        dir   = e[:dir].ljust(maxDir)
        type  = e[:type].ljust(maxType)
        "#{ind(1)}#{dir} #{type}#{e[:name]}#{comma}"
      end
    end

    # ── Logic declaration ─────────────────────────────────────────────────────

    def emitLogicDecl(sig, level)
      dim       = packedDim(sig.width)
      signedStr = sig.signed ? "signed " : ""
      typePart  = "logic #{signedStr}#{dim ? "#{dim} " : ""}"
      "#{ind(level)}#{typePart}#{sig.name};"
    end

    # ── Top-level statements ──────────────────────────────────────────────────

    def emitStmt(stmt, level)
      case stmt
      when AssignStmt
        ["#{ind(level)}assign #{stmt.lhs} = #{stmt.rhs};"]
      when AlwaysFF
        emitAlwaysFf(stmt, level)
      when AlwaysComb
        emitAlwaysComb(stmt, level)
      when Instance
        emitInstance(stmt, level)
      else
        ["#{ind(level)}// unknown statement: #{stmt.class}"]
      end
    end

    # ── always_ff ─────────────────────────────────────────────────────────────

    def emitAlwaysFf(stmt, level)
      lines = ["#{ind(level)}always_ff @(#{stmt.sensitivity}) begin"]
      stmt.body.each { |s| lines.concat(emitProcStmt(s, level + 1)) }
      lines << "#{ind(level)}end"
    end

    # ── always_comb ───────────────────────────────────────────────────────────

    def emitAlwaysComb(stmt, level)
      lines = ["#{ind(level)}always_comb begin"]
      stmt.body.each { |s| lines.concat(emitProcStmt(s, level + 1)) }
      lines << "#{ind(level)}end"
    end

    # ── Procedural statements ─────────────────────────────────────────────────

    def emitProcStmt(stmt, level)
      case stmt
      when NbAssign
        ["#{ind(level)}#{stmt.lhs} <= #{stmt.rhs};"]
      when BlockingAssign
        ["#{ind(level)}#{stmt.lhs} = #{stmt.rhs};"]
      when IfStmt
        emitIfStmt(stmt, level)
      else
        ["#{ind(level)}// unknown proc stmt: #{stmt.class}"]
      end
    end

    def emitIfStmt(stmt, level)
      lines = ["#{ind(level)}if (#{stmt.cond}) begin"]
      stmt.thenStmts.each { |s| lines.concat(emitProcStmt(s, level + 1)) }

      stmt.elsifClauses.each do |clause|
        lines << "#{ind(level)}end else if (#{clause[:cond]}) begin"
        clause[:stmts].each { |s| lines.concat(emitProcStmt(s, level + 1)) }
      end

      if stmt.elseStmts
        lines << "#{ind(level)}end else begin"
        stmt.elseStmts.each { |s| lines.concat(emitProcStmt(s, level + 1)) }
      end

      lines << "#{ind(level)}end"
    end

    # ── Module instantiation ──────────────────────────────────────────────────

    def emitInstance(inst, level)
      lines = []

      if inst.params.empty?
        lines << "#{ind(level)}#{inst.moduleName} #{inst.instName} ("
      else
        lines << "#{ind(level)}#{inst.moduleName} #("
        paramPairs = inst.params.to_a
        paramPairs.each_with_index do |(k, v), idx|
          comma = idx < paramPairs.size - 1 ? "," : ""
          lines << "#{ind(level + 1)}.#{k}(#{v})#{comma}"
        end
        lines << "#{ind(level)}) #{inst.instName} ("
      end

      connPairs = inst.connections.to_a
      connPairs.each_with_index do |(port, sig), idx|
        comma = idx < connPairs.size - 1 ? "," : ""
        lines << "#{ind(level + 1)}.#{port}(#{sig})#{comma}"
      end

      lines << "#{ind(level)});"
    end
  end
end
