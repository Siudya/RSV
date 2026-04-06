# frozen_string_literal: true

module RSV
  # Generates a Verilog-compatible wrapper module for an SV module.
  # Expands mem into flat Verilog-friendly ports.
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
      wiring_lines = emit_wiring(ports)
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

    def validate_ports(ports)
      ports.each do |port|
        next if port.width.is_a?(Integer)
        raise ArgumentError, "v_wrapper cannot flatten port '#{port.name}' with non-integer width"
      end
    end

    def flatten_all_ports(ports)
      result = []
      ports.each { |port| result.concat(flatten_port(port)) }
      result
    end

    def flatten_port(port)
      if has_unpacked_dims?(port)
        flatten_unpacked_port(port)
      else
        [FlatPort.new(dir_str(port.dir), port.width, port.name, port.name, port.signed)]
      end
    end

    def flatten_unpacked_port(port)
      count = port.unpacked_dims.reduce(1) { |acc, d| acc * dim_value(d) }
      count.times.map do |i|
        FlatPort.new(
          dir_str(port.dir), port.width,
          "#{port.name}_#{i}", "#{port.name}_sv[#{i}]",
          port.signed
        )
      end
    end

    def emit_wiring(ports)
      lines = []
      needs_wiring = ports.any? { |p| has_unpacked_dims?(p) }
      return lines unless needs_wiring

      lines << ""

      ports.each do |port|
        next unless has_unpacked_dims?(port)

        count = port.unpacked_dims.reduce(1) { |acc, d| acc * dim_value(d) }
        signed_str = port.signed ? "signed " : ""
        lines << "#{INDENT}wire #{signed_str}#{range_str(port.width)}#{port.name}_sv [0:#{count - 1}];"
        count.times do |i|
          flat_name = "#{port.name}_#{i}"
          if port.dir == :input
            lines << "#{INDENT}assign #{port.name}_sv[#{i}] = #{flat_name};"
          else
            lines << "#{INDENT}assign #{flat_name} = #{port.name}_sv[#{i}];"
          end
        end
      end
      lines
    end

    def port_connection_expr(port)
      has_unpacked_dims?(port) ? "#{port.name}_sv" : port.name
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
