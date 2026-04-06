# frozen_string_literal: true

module RSV
  # Base class for defining bundle types.
  #
  # Example:
  #   class MyBundle < RSV::BundleDef
  #     def build(width: 8)
  #       valid = input("valid", bit)
  #       data  = output("data",  uint(width))
  #     end
  #   end
  #
  #   dat_t = MyBundle.new
  #   r = reg("my_reg", dat_t)
  class BundleDef
    include TypeConstructors
    include TypeVariantRegistry

    attr_reader :fields, :type_name

    class << self
      def new(*args, **kwargs)
        raise ArgumentError, "BundleDef must be subclassed" if self == RSV::BundleDef

        build_type(*args, **kwargs)
      end

      def build_type(*args, **kwargs)
        bundle = allocate
        bundle.send(:initialize, *args, **kwargs)
        bundle.send(:finalize_type_name!)
        bundle.send(:to_data_type)
      end

      def bundle_def_instance
        @bundle_def_instance
      end
    end

    def initialize(*args, **kwargs)
      @fields = []
      @type_name = nil
      @type_name_finalized = false

      auto_build = self.class.instance_method(:initialize).owner == BundleDef &&
        self.class.instance_method(:build).owner != BundleDef
      build(*args, **kwargs) if auto_build
    end

    def build(*args, **kwargs)
    end

    def mem(*dims_and_target)
      compose_data_type(*dims_and_target)
    end

    def input(name, data_type)
      type = RSV.normalize_data_type(data_type)
      @fields << BundleFieldDef.new(name: name.to_s, data_type: type, dir: :input)
      @fields.last
    end

    def output(name, data_type)
      type = RSV.normalize_data_type(data_type)
      @fields << BundleFieldDef.new(name: name.to_s, data_type: type, dir: :output)
      @fields.last
    end

    private

    def finalize_type_name!
      return @type_name if @type_name_finalized

      base_name = default_type_name
      sv_sig = render_typedef(type_name: "__rsv_canonical_type__")
      @type_name = self.class.send(:resolve_registered_type_name, base_name, sv_sig)
      @type_name_finalized = true
      self.class.instance_variable_set(:@bundle_def_instance, self)
      @type_name
    end

    def default_type_name
      n = self.class.name.to_s.split("::").last
      n.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase + "_t"
    end

    def render_typedef(type_name:)
      lines = []
      lines << "typedef struct packed {"
      @fields.each do |f|
        dt = f.data_type
        if dt.bundle_type
          dim_str = ""
          dt.unpacked_dims.each { |d| dim_str += "[#{RSV.format_dim(d)}]" }
          lines << "  #{f.dir} #{dt.bundle_type.type_name} #{f.name}#{dim_str};"
        else
          signed_str = dt.signed ? "signed " : ""
          w = dt.width
          dim_str = w.is_a?(Integer) && w > 1 ? "[#{w - 1}:0] " : (w.is_a?(String) ? "[#{w}-1:0] " : "")
          unpacked = dt.unpacked_dims.map { |d| "[#{RSV.format_dim(d)}]" }.join
          lines << "  #{f.dir} logic #{signed_str}#{dim_str}#{f.name}#{unpacked};"
        end
      end
      lines << "} #{type_name};"
      lines.join("\n")
    end

    def to_data_type
      total_width = compute_total_width
      DataType.new(
        width: total_width,
        signed: false,
        init: nil,
        bundle_type: self
      )
    end

    def compute_total_width
      @fields.sum { |f| field_bit_width(f.data_type) }
    end

    def field_bit_width(dt)
      base = dt.width
      return 0 unless base.is_a?(Integer)
      base
    end

    def compose_data_type(*dims_and_target)
      raise ArgumentError, "mem expects dimensions + type" if dims_and_target.length < 2

      target = RSV.normalize_data_type(dims_and_target[-1])
      dims = dims_and_target[0...-1]
      dims = dims.first if dims.length == 1 && dims.first.is_a?(Array)
      dims = Array(dims).flatten.map { |d| RSV.normalize_expr(d) }

      target.append_dimensions(unpacked: dims)
    end
  end
end
