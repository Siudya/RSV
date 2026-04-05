# frozen_string_literal: true

module RSV
  # Converts an elaborated RSV AST into formatted SystemVerilog text.
  class Emitter
    INDENT = "  "

    def emit_module(mod)
      lines = []

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

      unless mod.locals.empty?
        lines.concat(emit_local_decls(mod.locals, 1))
        lines << ""
      end

      lines.concat(emit_stmt_list(mod.stmts, 1))

      lines << "" unless mod.stmts.empty?
      lines << "endmodule"

      lines.join("\n")
    end

    private

    def ind(level)
      INDENT * level
    end

    def packed_dim(width)
      return nil if width == 1 || width == "1"

      decl_range(width)
    end

    def packed_decl_dims(width, packed_dims)
      dims = packed_dims.map { |dim| decl_range(dim) }
      scalar = packed_dim(width)
      dims << scalar if scalar
      dims.join
    end

    def unpacked_decl_dims(unpacked_dims)
      unpacked_dims.map { |dim| decl_range(dim) }.join
    end

    def decl_range(length)
      length = RSV.normalize_expr(length)

      case length
      when LiteralExpr
        "[#{length.value - 1}:0]"
      when RawExpr
        text = length.source
        "[#{simple_decl_expr?(text) ? text : "(#{text})"}-1:0]"
      when SignalHandler
        "[#{length.name}-1:0]"
      when SvParamRef, GenvarRef
        "[#{length.name}-1:0]"
      else
        "[(" + emit_expr(length) + ")-1:0]"
      end
    end

    def simple_decl_expr?(text)
      text.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/)
    end

    def emit_params_list(params)
      params.each_with_index.map do |param, idx|
        comma = idx < params.size - 1 ? "," : ""
        type_part = param.param_type ? "#{param.param_type} " : ""
        "#{ind(1)}parameter #{type_part}#{param.name} = #{param.value}#{comma}"
      end
    end

    def emit_ports_list(ports)
      return [] if ports.empty?

      entries = ports.map do |port|
        signed_str = port.signed ? "signed " : ""
        dims = packed_decl_dims(port.width, port.packed_dims)
        type_part = "logic #{signed_str}#{dims}".rstrip
        name_part = "#{port.name}#{unpacked_decl_dims(port.unpacked_dims)}"
        { dir: port.dir.to_s, type: type_part, name: name_part, attr: port.attr }
      end

      max_dir = entries.map { |entry| entry[:dir].length }.max
      max_type = entries.map { |entry| entry[:type].length }.max

      entries.each_with_index.flat_map do |entry, idx|
        comma = idx < entries.size - 1 ? "," : ""
        dir = entry[:dir].ljust(max_dir)
        type = entry[:type].ljust(max_type)
        lines = []
        lines.concat(emit_attr_lines(entry[:attr], 1))
        lines << "#{ind(1)}#{dir} #{type} #{entry[:name]}#{comma}"
        lines
      end
    end

    def emit_local_decls(locals, level)
      entries = locals.map do |sig|
        packed_field = []
        packed_field << "signed" if sig.signed
        decl_dims = packed_decl_dims(sig.width, sig.packed_dims)
        packed_field << decl_dims unless decl_dims.empty?
        init_value = sig.init.nil? ? nil : emit_literal_init(sig.init, sig.width)
        is_const = sig.is_a?(ConstDecl)
        {
          kind: sig.sv_kind.to_s,
          packed: packed_field.join(" "),
          name: "#{sig.name}#{unpacked_decl_dims(sig.unpacked_dims)}",
          init: init_value,
          force_init: is_const,
          attr: sig.respond_to?(:attr) ? sig.attr : nil
        }
      end

      max_kind = entries.map { |entry| entry[:kind].length }.max
      max_packed = entries.map { |entry| entry[:packed].length }.max
      max_name = entries.map { |entry| entry[:name].length }.max

      entries.flat_map do |entry|
        prefix = entry[:kind].ljust(max_kind)
        prefix = "#{prefix} #{entry[:packed].ljust(max_packed)}" if max_packed.positive?
        lines = []
        lines.concat(emit_attr_lines(entry[:attr], level))

        if entry[:init]
          name_part = entry[:name].ljust(max_name)
          lines << "#{ind(level)}#{prefix} #{name_part} = #{entry[:init]};"
        else
          lines << "#{ind(level)}#{prefix} #{entry[:name]};"
        end

        lines
      end
    end

    def emit_literal_init(init, width)
      return init if init.is_a?(String)
      return init.to_s unless init.is_a?(Integer) && width.is_a?(Integer) && init >= 0

      "#{width}'h#{init.to_s(16)}"
    end

    def emit_attr_lines(attr, level)
      return [] if attr.nil? || attr.empty?

      parts = attr.map do |key, val|
        val.nil? ? key.to_s : "#{key} = #{val}"
      end
      ["#{ind(level)}(* #{parts.join(", ")} *)"]
    end

    def emit_stmt_list(stmts, level)
      lines = []
      idx = 0

      while idx < stmts.length
        stmt = stmts[idx]

        if stmt.is_a?(AssignStmt)
          assign_block = []
          while idx < stmts.length && stmts[idx].is_a?(AssignStmt)
            assign_block << stmts[idx]
            idx += 1
          end
          lines.concat(emit_assign_block(assign_block, level))
          prev_stmt = assign_block.last
        else
          lines.concat(emit_stmt(stmt, level))
          idx += 1
          prev_stmt = stmt
        end

        next_stmt = stmts[idx]
        lines << "" if next_stmt && blank_line_between?(prev_stmt, next_stmt)
      end

      lines
    end

    def emit_assign_block(stmts, level)
      lhs_entries = stmts.map { |stmt| emit_expr(stmt.lhs) }
      max_lhs = lhs_entries.map(&:length).max

      stmts.each_with_index.map do |stmt, idx|
        lhs = lhs_entries[idx].ljust(max_lhs)
        "#{ind(level)}assign #{lhs} = #{emit_expr(stmt.rhs)};"
      end
    end

    def emit_stmt(stmt, level)
      case stmt
      when AssignStmt
        ["#{ind(level)}assign #{emit_expr(stmt.lhs)} = #{emit_expr(stmt.rhs)};"]
      when AlwaysFF
        emit_always_ff(stmt, level)
      when AlwaysLatch
        emit_always_latch(stmt, level)
      when AlwaysComb
        emit_always_comb(stmt, level)
      when Instance
        emit_instance(stmt, level)
      when GenerateIf
        emit_generate_if(stmt, level)
      when GenerateFor
        emit_generate_for(stmt, level)
      when SvDefine
        value_part = stmt.value ? " #{stmt.value}" : ""
        ["`define #{stmt.macro_name}#{value_part}"]
      when SvUndef
        ["`undef #{stmt.macro_name}"]
      when SvIfdef
        emit_macro_cond("`ifdef", stmt, level)
      when SvIfndef
        emit_macro_cond("`ifndef", stmt, level)
      when SvPlugin
        emit_sv_plugin(stmt, level)
      else
        ["#{ind(level)}// unknown statement: #{stmt.class}"]
      end
    end

    def emit_always_ff(stmt, level)
      lines = ["#{ind(level)}always_ff @(#{stmt.sensitivity}) begin"]
      stmt.body.each { |proc_stmt| lines.concat(emit_proc_stmt(proc_stmt, level + 1)) }
      lines << "#{ind(level)}end"
    end

    def emit_always_comb(stmt, level)
      lines = ["#{ind(level)}always_comb begin"]
      stmt.body.each { |proc_stmt| lines.concat(emit_proc_stmt(proc_stmt, level + 1)) }
      lines << "#{ind(level)}end"
    end

    def emit_always_latch(stmt, level)
      lines = ["#{ind(level)}always_latch begin"]
      stmt.body.each { |proc_stmt| lines.concat(emit_proc_stmt(proc_stmt, level + 1)) }
      lines << "#{ind(level)}end"
    end

    def blank_line_between?(stmt, next_stmt)
      !(stmt.is_a?(AssignStmt) && next_stmt.is_a?(AssignStmt))
    end

    def emit_macro_cond(directive, stmt, level)
      lines = ["#{directive} #{stmt.macro_name}"]
      lines.concat(emit_stmt_list(stmt.body, level))

      stmt.elsif_clauses.each do |clause|
        lines << "`elsif #{clause[:macro_name]}"
        lines.concat(emit_stmt_list(clause[:body], level))
      end

      if stmt.else_body
        lines << "`else"
        lines.concat(emit_stmt_list(stmt.else_body, level))
      end

      lines << "`endif"
      lines
    end

    def emit_generate_block_body(locals, stmts, level)
      lines = []
      unless locals.empty?
        lines.concat(emit_local_decls(locals, level))
        lines << ""
      end
      lines.concat(emit_stmt_list(stmts, level))
      lines
    end

    def emit_generate_if(stmt, level)
      lines = ["#{ind(level)}if (#{emit_expr(stmt.cond)}) begin#{label_suffix(stmt.label)}"]
      lines.concat(emit_generate_block_body(stmt.locals, stmt.stmts, level + 1))

      stmt.elsif_clauses.each do |clause|
        lines << "#{ind(level)}end else if (#{emit_expr(clause[:cond])}) begin#{label_suffix(clause[:label])}"
        lines.concat(emit_generate_block_body(clause[:locals], clause[:stmts], level + 1))
      end

      if stmt.else_body
        lines << "#{ind(level)}end else begin#{label_suffix(stmt.else_body[:label])}"
        lines.concat(emit_generate_block_body(stmt.else_body[:locals], stmt.else_body[:stmts], level + 1))
      end

      lines << "#{ind(level)}end"
      lines
    end

    def emit_generate_for(stmt, level)
      lines = [
        "#{ind(level)}for (genvar #{stmt.genvar} = #{emit_expr(RSV.normalize_expr(stmt.start_val))}; " \
        "#{stmt.genvar} < #{emit_expr(RSV.normalize_expr(stmt.end_val))}; " \
        "#{stmt.genvar} = #{stmt.genvar} + 1) begin#{label_suffix(stmt.label)}"
      ]
      lines.concat(emit_generate_block_body(stmt.locals, stmt.stmts, level + 1))
      lines << "#{ind(level)}end"
      lines
    end

    def label_suffix(label)
      label ? " : #{label}" : ""
    end

    def emit_sv_plugin(stmt, level)
      stmt.code.lines.map { |line| "#{ind(level)}#{line.chomp}" }
    end

    def emit_proc_stmt(stmt, level)
      case stmt
      when NbAssign
        ["#{ind(level)}#{emit_expr(stmt.lhs)} <= #{emit_expr(stmt.rhs)};"]
      when BlockingAssign
        ["#{ind(level)}#{emit_expr(stmt.lhs)} = #{emit_expr(stmt.rhs)};"]
      when IfStmt
        emit_if_stmt(stmt, level)
      when ForStmt
        emit_for_stmt(stmt, level)
      when MuxCaseStmt
        emit_mux_case_inline(stmt, level)
      when SvPlugin
        emit_sv_plugin(stmt, level)
      else
        ["#{ind(level)}// unknown proc stmt: #{stmt.class}"]
      end
    end

    def emit_if_stmt(stmt, level)
      lines = ["#{ind(level)}if (#{emit_expr(stmt.cond)}) begin"]
      stmt.then_stmts.each { |proc_stmt| lines.concat(emit_proc_stmt(proc_stmt, level + 1)) }

      stmt.elsif_clauses.each do |clause|
        lines << "#{ind(level)}end else if (#{emit_expr(clause[:cond])}) begin"
        clause[:stmts].each { |proc_stmt| lines.concat(emit_proc_stmt(proc_stmt, level + 1)) }
      end

      if stmt.else_stmts
        lines << "#{ind(level)}end else begin"
        stmt.else_stmts.each { |proc_stmt| lines.concat(emit_proc_stmt(proc_stmt, level + 1)) }
      end

      lines << "#{ind(level)}end"
    end

    def emit_for_stmt(stmt, level)
      lines = [
        "#{ind(level)}for (int #{stmt.index_name} = 0; #{stmt.index_name} < #{emit_expr(stmt.limit)}; #{stmt.index_name} = #{stmt.index_name} + 1) begin"
      ]
      stmt.body.each { |proc_stmt| lines.concat(emit_proc_stmt(proc_stmt, level + 1)) }
      lines << "#{ind(level)}end"
    end

    def emit_instance(inst, level)
      lines = []

      if inst.params.empty?
        lines << "#{ind(level)}#{inst.module_name} #{inst.inst_name} ("
      else
        lines << "#{ind(level)}#{inst.module_name} #("
        param_pairs = inst.params.to_a
        param_pairs.each_with_index do |(key, value), idx|
          comma = idx < param_pairs.size - 1 ? "," : ""
          lines << "#{ind(level + 1)}.#{key}(#{value})#{comma}"
        end
        lines << "#{ind(level)}) #{inst.inst_name} ("
      end

      conn_pairs = inst.connections.to_a
      conn_pairs.each_with_index do |(port, sig), idx|
        comma = idx < conn_pairs.size - 1 ? "," : ""
        lines << "#{ind(level + 1)}.#{port}(#{emit_expr(sig)})#{comma}"
      end

      lines << "#{ind(level)});"
    end

    def emit_mux_case_inline(stmt, level)
      sel_width = stmt.sel.width
      dats = stmt.dats
      lhs_name = emit_expr(stmt.lhs)
      sel_name = emit_expr(stmt.sel)

      dat_entries = collect_mux_entries(dats)
      raise ArgumentError, "mux1h/muxp dats length must match sel width" if dat_entries.size != sel_width

      case_keyword = stmt.case_type == :unique ? "unique casez" : "priority casez"
      lines = []
      lines << "#{ind(level)}#{case_keyword} (#{sel_name})"

      if stmt.case_type == :priority
        lsb_first = stmt.lsb_first
        indices = lsb_first ? (0...sel_width).to_a : (0...sel_width).to_a.reverse
        lowest_priority_idx = lsb_first ? sel_width - 1 : 0

        indices.each do |i|
          pattern = build_muxp_pattern(sel_width, i, lsb_first)
          lines << "#{ind(level + 1)}#{sel_width}'b#{pattern}: #{lhs_name} = #{emit_expr(dat_entries[i])};"
        end

        lines << "#{ind(level + 1)}default: #{lhs_name} = #{emit_expr(dat_entries[lowest_priority_idx])};"
      else
        (0...sel_width).each do |i|
          pattern = build_mux1h_pattern(sel_width, i)
          lines << "#{ind(level + 1)}#{sel_width}'b#{pattern}: #{lhs_name} = #{emit_expr(dat_entries[i])};"
        end

        zero_width = RSV.infer_expr_width(stmt.lhs)
        zero_lit = zero_width ? "#{zero_width}'d0" : "'0"
        lines << "#{ind(level + 1)}default: #{lhs_name} = #{zero_lit};"
      end

      lines << "#{ind(level)}endcase"
      lines
    end

    def collect_mux_entries(dats)
      if dats.is_a?(SignalHandler) && (!dats.unpacked_dims.empty? || !dats.packed_dims.empty?)
        dim = if !dats.unpacked_dims.empty?
          RSV.dimension_value(dats.unpacked_dims.first)
        else
          RSV.dimension_value(dats.packed_dims.first)
        end
        return (0...dim).map { |i| IndexExpr.new(dats, LiteralExpr.new(i)) }
      end

      raise ArgumentError, "mux1h/muxp dats must be an arr or mem signal"
    end

    def build_mux1h_pattern(width, idx)
      # one-hot exact: only bit idx is 1, rest are 0
      (0...width).reverse_each.map { |i| i == idx ? "1" : "0" }.join
    end

    def build_muxp_pattern(width, idx, lsb_first)
      # For lsb_first: sel[0] has highest priority
      #   bit idx=1, bits with higher priority (< idx) = 0, others = ?
      # For msb_first: sel[N-1] has highest priority
      #   bit idx=1, bits with higher priority (> idx) = 0, others = ?
      (0...width).reverse_each.map do |i|
        if i == idx
          "1"
        elsif lsb_first ? (i < idx) : (i > idx)
          "0"
        else
          "?"
        end
      end.join
    end

    def emit_expr(expr, parent_precedence = 0)
      expr = RSV.normalize_expr(expr)

      case expr
      when ClockSignal
        expr.name
      when ResetSignal
        expr.name
      when InstancePortHandler
        expr.name
      when SignalHandler
        expr.name
      when RawExpr
        expr.source
      when LiteralExpr
        emit_literal_expr(expr)
      when IndexExpr
        "#{emit_expr(expr.base, precedence_for(:index))}[#{emit_expr(expr.index)}]"
      when RangeSelectExpr
        "#{emit_expr(expr.base, precedence_for(:index))}[#{emit_expr(expr.msb)}:#{emit_expr(expr.lsb)}]"
      when IndexedPartSelectExpr
        "#{emit_expr(expr.base, precedence_for(:index))}[#{emit_expr(expr.start)} #{emit_indexed_direction(expr.direction)} #{emit_expr(expr.part_width)}]"
      when UnaryExpr
        emit_unary_expr(expr, parent_precedence)
      when ParenExpr
        "(#{emit_expr(expr.inner)})"
      when BinaryExpr
        emit_binary_expr(expr, parent_precedence)
      when AsSintExpr
        "$signed(#{emit_expr(expr.operand)})"
      when MuxExpr
        sel_str = emit_expr(expr.sel, 6)
        a_str = emit_expr(expr.a, 6)
        b_str = emit_expr(expr.b, 6)
        rendered = "#{sel_str} ? #{a_str} : #{b_str}"
        parent_precedence > 5 ? "(#{rendered})" : rendered
      when CatExpr
        "{#{expr.parts.map { |p| emit_expr(p) }.join(", ")}}"
      when FillExpr
        "{#{emit_expr(expr.count)}{#{emit_expr(expr.part)}}}"
      when PackedCollectionExpr
        "{#{expr.parts_low_to_high.reverse.map { |p| emit_expr(p) }.join(", ")}}"
      when MacroRef
        "`#{expr.macro_name}"
      when GenvarRef
        expr.name
      when SvParamRef
        expr.name
      else
        expr.to_s
      end
    end

    def emit_literal_expr(expr)
      if !expr.width.is_a?(Integer)
        return "'0" if expr.value == 0 && expr.format == :hex

        return expr.value.to_s
      end

      return expr.value.to_s if expr.width.nil?

      base = expr.format == :hex ? "h" : "d"
      value = expr.format == :hex ? expr.value.to_s(16) : expr.value.to_s
      "#{expr.width}'#{base}#{value}"
    end

    def emit_binary_expr(expr, parent_precedence)
      prec = precedence_for(expr.op)
      lhs = emit_expr(expr.lhs, prec)
      rhs = emit_expr(expr.rhs, prec + 1)
      rendered = "#{lhs} #{emit_operator(expr.op)} #{rhs}"
      prec < parent_precedence ? "(#{rendered})" : rendered
    end

    def emit_unary_expr(expr, parent_precedence)
      prec = precedence_for(expr.op)
      operand = emit_expr(expr.operand, prec)
      rendered = "#{emit_unary_operator(expr.op)}#{operand}"
      prec < parent_precedence ? "(#{rendered})" : rendered
    end

    def emit_operator(op)
      case op
      when :<<
        "<<"
      when :>>
        ">>"
      when :<=
        "<="
      when :>=
        ">="
      when :==
        "=="
      when :!=
        "!="
      when :logic_and
        "&&"
      when :logic_or
        "||"
      else
        op.to_s
      end
    end

    def emit_unary_operator(op)
      case op
      when :!
        "!"
      when :~
        "~"
      when :reduce_or
        "|"
      when :reduce_and
        "&"
      else
        op.to_s
      end
    end

    def emit_indexed_direction(direction)
      case direction
      when :+
        "+:"
      when :-
        "-:"
      else
        direction.to_s
      end
    end

    def precedence_for(op)
      case op
      when :index
        100
      when :!, :~, :reduce_or, :reduce_and
        80
      when :*, :/, :%
        70
      when :+, :-
        60
      when :<<, :>>
        50
      when :&
        30
      when :^
        25
      when :|
        20
      when :<, :<=, :>, :>=
        20
      when :==, :!=
        18
      when :logic_and
        15
      when :logic_or
        10
      else
        10
      end
    end
  end
end
