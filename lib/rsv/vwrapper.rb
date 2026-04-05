# frozen_string_literal: true

module RSV
  # Generates a Verilog-compatible wrapper module for an SV module.
  # Exposes flat ports at the top level (Verilog-friendly), while
  # internally using SV syntax for unpacked array conversions.
  class VerilogWrapperGenerator
    INDENT = "  "

    def generate(mod, wrapper_name)
      ports = mod.ports
      validate_ports(ports)
      flat_ports = flatten_ports(ports)
      lines = []

      lines << "module #{wrapper_name} ("
      flat_ports.each_with_index do |fp, idx|
        comma = idx < flat_ports.size - 1 ? "," : ""
        lines << "#{INDENT}#{fp[:dir_str]} #{fp[:range_str]}#{fp[:name]}#{comma}"
      end
      lines << ");"

      # Unpacked array ports need SV array wires + individual assignments
      unpacked_ports = ports.select { |p| has_unpacked_dims?(p) }
      if unpacked_ports.any?
        lines << ""
        unpacked_ports.each do |port|
          elem_w = compute_packed_width(port)
          count = unpacked_count(port)
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
      end

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
        conn = has_unpacked_dims?(port) ? "#{port.name}_sv" : port.name
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

    def compute_packed_width(port)
      total = port.width
      port.packed_dims.each { |d| total *= dim_value(d) }
      total
    end

    def unpacked_count(port)
      port.unpacked_dims.reduce(1) { |acc, d| acc * dim_value(d) }
    end

    def range_str(width)
      width == 1 ? "       " : "[#{(width - 1).to_s.rjust(4)}:0] "
    end

    def flatten_ports(ports)
      result = []
      ports.each do |port|
        dir_str = case port.dir
                  when :input then "input "
                  when :output then "output"
                  when :inout then "inout "
                  end

        if has_unpacked_dims?(port)
          elem_width = compute_packed_width(port)
          count = unpacked_count(port)
          count.times do |i|
            result << {
              name: "#{port.name}_#{i}",
              dir_str: dir_str,
              range_str: range_str(elem_width)
            }
          end
        else
          total = compute_packed_width(port)
          result << { name: port.name, dir_str: dir_str, range_str: range_str(total) }
        end
      end
      result
    end
  end
end
