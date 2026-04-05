# frozen_string_literal: true

module RSV
  # Generates a Verilog-compatible wrapper module for an SV module.
  # Expands interfaces, bundles, and arr/mem into flat Verilog-friendly ports.
  class VerilogWrapperGenerator
    INDENT = "  "

    # A flattened leaf port: direction, bit width, flat name, SV path for wiring.
    FlatPort = Struct.new(:dir_str, :width, :name, :sv_path, :signed)

    def generate(mod, wrapper_name)
      ports = mod.ports
      validate_ports(ports)
      flat_ports = flatten_all_ports(ports)
      lines = []

      # Module header with flat port list
      lines << "module #{wrapper_name} ("
      flat_ports.each_with_index do |fp, idx|
        comma = idx < flat_ports.size - 1 ? "," : ""
        lines << "#{INDENT}#{fp.dir_str} #{range_str(fp.width)}#{fp.name}#{comma}"
      end
      lines << ");"

      # Internal wires and assignments for complex ports
      wiring_lines = emit_wiring(ports, flat_ports)
      lines.concat(wiring_lines) if wiring_lines.any?

      # Instantiate inner SV module
      lines << ""
      if mod.params.any?
        lines << "#{INDENT}#{mod.module_name} #("
        mod.params.each_with_index do |param, idx|
          comma = idx < mod.params.size - 1 ? "," : ""
          lines << "#{INDENT}#{INDENT}.#{param.name}(#{param.value})#{comma}"
        end
        lines << "#{INDENT}) u_inner ("
      else
        lines << "#{INDENT}#{mod.module_name} u_inner ("
      end

      ports.each_with_index do |port, idx|
        comma = idx < ports.size - 1 ? "," : ""
        conn = port_connection_expr(port)
        lines << "#{INDENT}#{INDENT}.#{port.name}(#{conn})#{comma}"
      end
      lines << "#{INDENT});"

      lines << ""
      lines << "endmodule"
      lines.join("\n")
    end

    private

    # ── Validation ─────────────────────────────────────────────────────────

    def validate_ports(ports)
      ports.each do |port|
        next if port.dir == :intf
        next if port.bundle_type
        next if port.width.is_a?(Integer)

        raise ArgumentError, "v_wrapper cannot flatten port '#{port.name}' with non-integer width"
      end
    end

    # ── Flatten ports to leaf-level scalar Verilog ports ────────────────────

    def flatten_all_ports(ports)
      result = []
      ports.each { |port| result.concat(flatten_port(port)) }
      result
    end

    def flatten_port(port)
      if port.dir == :intf && port.intf_type
        flatten_intf_port(port)
      elsif port.bundle_type
        flatten_bundle_port(port)
      elsif has_unpacked_dims?(port)
        flatten_unpacked_port(port)
      else
        total = compute_packed_width_from(port.width, port.packed_dims)
        [FlatPort.new(dir_str(port.dir), total, port.name, port.name, port.signed)]
      end
    end

    # Expand interface port: each field becomes one or more flat ports.
    def flatten_intf_port(port)
      intf_def = port.intf_type[:klass]
      modport = port.intf_type[:modport] || "mst"
      result = []

      intf_def.fields.each do |f|
        field_dir = resolve_intf_field_dir(f[:dir], modport)
        dt = f[:data_type]
        prefix = "#{port.name}_#{f[:name]}"
        sv_path = "#{port.name}_sv.#{f[:name]}"
        result.concat(flatten_data_type(prefix, sv_path, field_dir, dt))
      end
      result
    end

    # Expand bundle-typed port: each field becomes one or more flat ports.
    def flatten_bundle_port(port)
      result = []
      dir = port.dir
      bundle = port.bundle_type
      # Handle arr/mem of bundle
      unpacked = port.unpacked_dims
      packed_extra = port.packed_dims

      if !unpacked.empty?
        # mem(N, BundleType) — expand unpacked dims then fields
        count = unpacked.reduce(1) { |acc, d| acc * dim_value(d) }
        count.times do |i|
          bundle.fields.each do |f|
            prefix = "#{port.name}_#{i}_#{f.name}"
            sv_path = "#{port.name}_sv[#{i}].#{f.name}"
            result.concat(flatten_data_type(prefix, sv_path, dir, f.data_type))
          end
        end
      elsif !packed_extra.empty?
        # arr(N, BundleType) — packed array of struct, flatten to bit vector
        elem_w = compute_bundle_width(bundle)
        total = elem_w
        packed_extra.each { |d| total *= dim_value(d) }
        result << FlatPort.new(dir_str(dir), total, port.name, port.name, false)
      else
        # Plain bundle
        bundle.fields.each do |f|
          prefix = "#{port.name}_#{f.name}"
          sv_path = "#{port.name}_sv.#{f.name}"
          result.concat(flatten_data_type(prefix, sv_path, dir, f.data_type))
        end
      end
      result
    end

    # Recursively flatten a DataType to leaf ports.
    def flatten_data_type(prefix, sv_path, dir, dt)
      if dt.bundle_type
        # Nested bundle
        result = []
        unpacked = dt.unpacked_dims
        packed_extra = dt.packed_dims

        if !unpacked.empty?
          count = unpacked.reduce(1) { |acc, d| acc * dim_value(d) }
          count.times do |i|
            dt.bundle_type.fields.each do |f|
              result.concat(flatten_data_type(
                "#{prefix}_#{i}_#{f.name}", "#{sv_path}[#{i}].#{f.name}",
                dir, f.data_type
              ))
            end
          end
        elsif !packed_extra.empty?
          elem_w = compute_bundle_width(dt.bundle_type)
          total = elem_w
          packed_extra.each { |d| total *= dim_value(d) }
          result << FlatPort.new(dir_str(dir), total, prefix, sv_path, false)
        else
          dt.bundle_type.fields.each do |f|
            result.concat(flatten_data_type(
              "#{prefix}_#{f.name}", "#{sv_path}.#{f.name}",
              dir, f.data_type
            ))
          end
        end
        result
      elsif !dt.unpacked_dims.empty?
        # Unpacked memory — expand to individual elements
        elem_w = compute_packed_width_from(dt.width, dt.packed_dims)
        count = dt.unpacked_dims.reduce(1) { |acc, d| acc * dim_value(d) }
        count.times.map do |i|
          FlatPort.new(dir_str(dir), elem_w, "#{prefix}_#{i}", "#{sv_path}[#{i}]", dt.signed)
        end
      else
        total = compute_packed_width_from(dt.width, dt.packed_dims)
        [FlatPort.new(dir_str(dir), total, prefix, sv_path, dt.signed)]
      end
    end

    # Expand unpacked (mem) non-bundle port.
    def flatten_unpacked_port(port)
      elem_w = compute_packed_width_from(port.width, port.packed_dims)
      count = port.unpacked_dims.reduce(1) { |acc, d| acc * dim_value(d) }
      count.times.map do |i|
        FlatPort.new(
          dir_str(port.dir), elem_w,
          "#{port.name}_#{i}", "#{port.name}_sv[#{i}]",
          port.signed
        )
      end
    end

    # ── Wiring: internal SV wires + assign statements ──────────────────────

    def emit_wiring(ports, flat_ports)
      lines = []
      needs_wiring = ports.any? { |p| complex_port?(p) }
      return lines unless needs_wiring

      lines << ""

      ports.each do |port|
        if port.dir == :intf && port.intf_type
          emit_intf_wiring(lines, port, flat_ports)
        elsif port.bundle_type
          emit_bundle_wiring(lines, port, flat_ports)
        elsif has_unpacked_dims?(port)
          emit_unpacked_wiring(lines, port)
        end
      end
      lines
    end

    def emit_intf_wiring(lines, port, flat_ports)
      intf_def = port.intf_type[:klass]
      type_name = port.intf_type[:type_name]
      # Declare a local interface instance (no modport constraint)
      lines << "#{INDENT}#{type_name} #{port.name}_sv();"

      # Assign flat ports ↔ interface fields
      modport = port.intf_type[:modport] || "mst"
      intf_def.fields.each do |f|
        field_dir = resolve_intf_field_dir(f[:dir], modport)
        dt = f[:data_type]
        prefix = "#{port.name}_#{f[:name]}"
        sv_path = "#{port.name}_sv.#{f[:name]}"
        emit_leaf_assigns(lines, prefix, sv_path, field_dir, dt)
      end
    end

    def emit_bundle_wiring(lines, port, flat_ports)
      bundle = port.bundle_type
      type_name = bundle.type_name
      unpacked = port.unpacked_dims
      dir = port.dir

      if !unpacked.empty?
        count = unpacked.reduce(1) { |acc, d| acc * dim_value(d) }
        lines << "#{INDENT}#{type_name} #{port.name}_sv [0:#{count - 1}];"
        count.times do |i|
          bundle.fields.each do |f|
            prefix = "#{port.name}_#{i}_#{f.name}"
            sv_path = "#{port.name}_sv[#{i}].#{f.name}"
            emit_leaf_assigns(lines, prefix, sv_path, dir, f.data_type)
          end
        end
      elsif port.packed_dims.empty?
        # Plain bundle
        lines << "#{INDENT}#{type_name} #{port.name}_sv;"
        bundle.fields.each do |f|
          prefix = "#{port.name}_#{f.name}"
          sv_path = "#{port.name}_sv.#{f.name}"
          emit_leaf_assigns(lines, prefix, sv_path, dir, f.data_type)
        end
      end
      # Packed arr of bundle doesn't need wiring — it's a flat bit vector
    end

    def emit_unpacked_wiring(lines, port)
      elem_w = compute_packed_width_from(port.width, port.packed_dims)
      count = port.unpacked_dims.reduce(1) { |acc, d| acc * dim_value(d) }
      signed_str = port.signed ? "signed " : ""
      lines << "#{INDENT}wire #{signed_str}#{range_str(elem_w)}#{port.name}_sv [0:#{count - 1}];"
      count.times do |i|
        flat_name = "#{port.name}_#{i}"
        if port.dir == :input
          lines << "#{INDENT}assign #{port.name}_sv[#{i}] = #{flat_name};"
        else
          lines << "#{INDENT}assign #{flat_name} = #{port.name}_sv[#{i}];"
        end
      end
    end

    # Recursively emit assign statements for leaf ports.
    def emit_leaf_assigns(lines, prefix, sv_path, dir, dt)
      if dt.bundle_type
        unpacked = dt.unpacked_dims
        if !unpacked.empty?
          count = unpacked.reduce(1) { |acc, d| acc * dim_value(d) }
          count.times do |i|
            dt.bundle_type.fields.each do |f|
              emit_leaf_assigns(lines,
                "#{prefix}_#{i}_#{f.name}", "#{sv_path}[#{i}].#{f.name}",
                dir, f.data_type)
            end
          end
        elsif dt.packed_dims.empty?
          dt.bundle_type.fields.each do |f|
            emit_leaf_assigns(lines,
              "#{prefix}_#{f.name}", "#{sv_path}.#{f.name}",
              dir, f.data_type)
          end
        else
          # Packed arr of bundle → flat bit vector, direct assign
          emit_assign(lines, prefix, sv_path, dir)
        end
      elsif !dt.unpacked_dims.empty?
        count = dt.unpacked_dims.reduce(1) { |acc, d| acc * dim_value(d) }
        count.times do |i|
          emit_assign(lines, "#{prefix}_#{i}", "#{sv_path}[#{i}]", dir)
        end
      else
        emit_assign(lines, prefix, sv_path, dir)
      end
    end

    def emit_assign(lines, flat_name, sv_path, dir)
      if dir == :input
        lines << "#{INDENT}assign #{sv_path} = #{flat_name};"
      else
        lines << "#{INDENT}assign #{flat_name} = #{sv_path};"
      end
    end

    # ── Port connection expressions for inner module instantiation ──────────

    def port_connection_expr(port)
      if port.dir == :intf && port.intf_type
        "#{port.name}_sv"
      elsif port.bundle_type && port.packed_dims.empty? && !has_unpacked_dims?(port)
        "#{port.name}_sv"
      elsif port.bundle_type && !port.unpacked_dims.empty?
        "#{port.name}_sv"
      elsif has_unpacked_dims?(port)
        "#{port.name}_sv"
      else
        port.name
      end
    end

    # ── Helpers ─────────────────────────────────────────────────────────────

    def complex_port?(port)
      (port.dir == :intf && port.intf_type) ||
        (port.bundle_type && (port.packed_dims.empty? || !port.unpacked_dims.empty?)) ||
        has_unpacked_dims?(port)
    end

    def has_unpacked_dims?(port)
      !port.unpacked_dims.empty?
    end

    def dim_value(expr)
      case expr
      when LiteralExpr then expr.value
      when Integer then expr
      else raise ArgumentError, "cannot flatten non-constant dimension: #{expr.class}"
      end
    end

    def compute_packed_width_from(width, packed_dims)
      total = width
      packed_dims.each { |d| total *= dim_value(d) }
      total
    end

    def compute_bundle_width(bundle)
      bundle.fields.sum { |f| field_bit_width(f.data_type) }
    end

    def field_bit_width(dt)
      if dt.bundle_type
        base = compute_bundle_width(dt.bundle_type)
      else
        base = dt.width
      end
      return 0 unless base.is_a?(Integer)
      total = base
      dt.packed_dims.each { |d| return 0 unless (v = dim_value(d)).is_a?(Integer); total *= v }
      dt.unpacked_dims.each { |d| return 0 unless (v = dim_value(d)).is_a?(Integer); total *= v }
      total
    end

    # Resolve interface field direction w.r.t. the module's modport.
    # mst → as-declared; slv → reversed.
    def resolve_intf_field_dir(field_dir, modport)
      if modport == "slv"
        field_dir == "output" ? :input : :output
      else
        field_dir == "output" ? :output : :input
      end
    end

    def dir_str(dir)
      case dir
      when :input then "input "
      when :output then "output"
      when :inout then "inout "
      else "input "
      end
    end

    def range_str(width)
      width == 1 ? "       " : "[#{(width - 1).to_s.rjust(4)}:0] "
    end
  end
end
