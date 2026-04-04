# frozen_string_literal: true

module RSV
  # Converts an elaborated RSV AST into formatted SystemVerilog text.
  class Emitter
    INDENT = "  "

    def emitModule(mod)
      lines = []

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

      unless mod.locals.empty?
        lines.concat(emitLocalDecls(mod.locals, 1))
        lines << ""
      end

      mod.stmts.each_with_index do |stmt, idx|
        lines.concat(emitStmt(stmt, 1))
        nextStmt = mod.stmts[idx + 1]
        lines << "" if nextStmt && blankLineBetween?(stmt, nextStmt)
      end

      lines << "" unless mod.stmts.empty?
      lines << "endmodule"

      lines.join("\n")
    end

    private

    def ind(level)
      INDENT * level
    end

    def packedDim(width)
      return nil if width == 1 || width == "1"

      if width.is_a?(Integer)
        "[#{width - 1}:0]"
      else
        "[#{width}-1:0]"
      end
    end

    def emitParamsList(params)
      params.each_with_index.map do |param, idx|
        comma = idx < params.size - 1 ? "," : ""
        typePart = param.paramType ? "#{param.paramType} " : ""
        "#{ind(1)}parameter #{typePart}#{param.name} = #{param.value}#{comma}"
      end
    end

    def emitPortsList(ports)
      return [] if ports.empty?

      entries = ports.map do |port|
        dim = packedDim(port.width)
        signedStr = port.signed ? "signed " : ""
        typePart = "logic #{signedStr}#{dim ? "#{dim} " : ""}"
        { dir: port.dir.to_s, type: typePart, name: port.name }
      end

      maxDir = entries.map { |entry| entry[:dir].length }.max
      maxType = entries.map { |entry| entry[:type].length }.max

      entries.each_with_index.map do |entry, idx|
        comma = idx < entries.size - 1 ? "," : ""
        dir = entry[:dir].ljust(maxDir)
        type = entry[:type].ljust(maxType)
        "#{ind(1)}#{dir} #{type}#{entry[:name]}#{comma}"
      end
    end

    def emitLocalDecls(locals, level)
      entries = locals.map do |sig|
        dim = packedDim(sig.width)
        widthTokens = []
        widthTokens << "signed" if sig.signed
        widthTokens << dim if dim
        initValue = sig.init.nil? ? nil : emitLiteralInit(sig.init, sig.width)
        { kind: sig.svKind.to_s, width: widthTokens.join(" "), name: sig.name, init: initValue }
      end

      maxKind = entries.map { |entry| entry[:kind].length }.max
      maxWidth = entries.map { |entry| entry[:width].length }.max
      maxName = entries.map { |entry| entry[:name].length }.max

      entries.map do |entry|
        prefix = entry[:kind].ljust(maxKind)
        prefix = "#{prefix} #{entry[:width].ljust(maxWidth)}" if maxWidth.positive?

        if entry[:init]
          namePart = entry[:name].ljust(maxName)
          "#{ind(level)}#{prefix} #{namePart} = #{entry[:init]};"
        else
          "#{ind(level)}#{prefix} #{entry[:name]};"
        end
      end
    end

    def emitLiteralInit(init, width)
      return init if init.is_a?(String)
      return init.to_s unless init.is_a?(Integer) && width.is_a?(Integer) && init >= 0

      "#{width}'h#{init.to_s(16)}"
    end

    def emitStmt(stmt, level)
      case stmt
      when AssignStmt
        ["#{ind(level)}assign #{emitExpr(stmt.lhs)} = #{emitExpr(stmt.rhs)};"]
      when AlwaysFF
        emitAlwaysFf(stmt, level)
      when AlwaysLatch
        emitAlwaysLatch(stmt, level)
      when AlwaysComb
        emitAlwaysComb(stmt, level)
      when Instance
        emitInstance(stmt, level)
      else
        ["#{ind(level)}// unknown statement: #{stmt.class}"]
      end
    end

    def emitAlwaysFf(stmt, level)
      lines = ["#{ind(level)}always_ff @(#{stmt.sensitivity}) begin"]
      stmt.body.each { |procStmt| lines.concat(emitProcStmt(procStmt, level + 1)) }
      lines << "#{ind(level)}end"
    end

    def emitAlwaysComb(stmt, level)
      lines = ["#{ind(level)}always_comb begin"]
      stmt.body.each { |procStmt| lines.concat(emitProcStmt(procStmt, level + 1)) }
      lines << "#{ind(level)}end"
    end

    def emitAlwaysLatch(stmt, level)
      lines = ["#{ind(level)}always_latch begin"]
      stmt.body.each { |procStmt| lines.concat(emitProcStmt(procStmt, level + 1)) }
      lines << "#{ind(level)}end"
    end

    def blankLineBetween?(stmt, nextStmt)
      !(stmt.is_a?(AssignStmt) && nextStmt.is_a?(AssignStmt))
    end

    def emitProcStmt(stmt, level)
      case stmt
      when NbAssign
        ["#{ind(level)}#{emitExpr(stmt.lhs)} <= #{emitExpr(stmt.rhs)};"]
      when BlockingAssign
        ["#{ind(level)}#{emitExpr(stmt.lhs)} = #{emitExpr(stmt.rhs)};"]
      when IfStmt
        emitIfStmt(stmt, level)
      else
        ["#{ind(level)}// unknown proc stmt: #{stmt.class}"]
      end
    end

    def emitIfStmt(stmt, level)
      lines = ["#{ind(level)}if (#{emitExpr(stmt.cond)}) begin"]
      stmt.thenStmts.each { |procStmt| lines.concat(emitProcStmt(procStmt, level + 1)) }

      stmt.elsifClauses.each do |clause|
        lines << "#{ind(level)}end else if (#{emitExpr(clause[:cond])}) begin"
        clause[:stmts].each { |procStmt| lines.concat(emitProcStmt(procStmt, level + 1)) }
      end

      if stmt.elseStmts
        lines << "#{ind(level)}end else begin"
        stmt.elseStmts.each { |procStmt| lines.concat(emitProcStmt(procStmt, level + 1)) }
      end

      lines << "#{ind(level)}end"
    end

    def emitInstance(inst, level)
      lines = []

      if inst.params.empty?
        lines << "#{ind(level)}#{inst.moduleName} #{inst.instName} ("
      else
        lines << "#{ind(level)}#{inst.moduleName} #("
        paramPairs = inst.params.to_a
        paramPairs.each_with_index do |(key, value), idx|
          comma = idx < paramPairs.size - 1 ? "," : ""
          lines << "#{ind(level + 1)}.#{key}(#{value})#{comma}"
        end
        lines << "#{ind(level)}) #{inst.instName} ("
      end

      connPairs = inst.connections.to_a
      connPairs.each_with_index do |(port, sig), idx|
        comma = idx < connPairs.size - 1 ? "," : ""
        lines << "#{ind(level + 1)}.#{port}(#{emitExpr(sig)})#{comma}"
      end

      lines << "#{ind(level)});"
    end

    def emitExpr(expr, parentPrecedence = 0)
      expr = RSV.normalizeExpr(expr)

      case expr
      when SignalHandler
        expr.name
      when RawExpr
        expr.source
      when LiteralExpr
        emitLiteralExpr(expr)
      when IndexExpr
        "#{emitExpr(expr.base, precedenceFor(:index))}[#{emitExpr(expr.index)}]"
      when BinaryExpr
        emitBinaryExpr(expr, parentPrecedence)
      else
        expr.to_s
      end
    end

    def emitLiteralExpr(expr)
      if !expr.width.is_a?(Integer)
        return "'0" if expr.value == 0 && expr.format == :hex

        return expr.value.to_s
      end

      return expr.value.to_s if expr.width.nil?

      base = expr.format == :hex ? "h" : "d"
      value = expr.format == :hex ? expr.value.to_s(16) : expr.value.to_s
      "#{expr.width}'#{base}#{value}"
    end

    def emitBinaryExpr(expr, parentPrecedence)
      prec = precedenceFor(expr.op)
      lhs = emitExpr(expr.lhs, prec + 1)
      rhs = emitExpr(expr.rhs, prec + 1)
      rendered = "#{lhs} #{expr.op} #{rhs}"
      prec < parentPrecedence ? "(#{rendered})" : rendered
    end

    def precedenceFor(op)
      case op
      when :index
        100
      when :<, :>, :>=
        20
      when :&, :|, :^
        30
      when :+, :-
        40
      else
        10
      end
    end
  end
end
