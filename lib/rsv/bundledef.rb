# frozen_string_literal: true

module RSV
  # Curried builder for bundles with sv_param declarations.
  class CurriedBundleBuilder
    def initialize(klass, *args, **kwargs)
      @klass = klass
      @args = args
      @kwargs = kwargs
      @sv_param_overrides = nil
      @result = nil
    end

    def call(**kwargs)
      if @sv_param_overrides.nil?
        @sv_param_overrides = kwargs
        self
      else
        finalize(**kwargs)
      end
    end

    def method_missing(name, *args, **kwargs, &block)
      finalize.send(name, *args, **kwargs, &block)
    end

    def respond_to_missing?(name, include_private = false)
      true
    end

    private

    def finalize(**meta_params)
      return @result if @result

      @sv_param_overrides ||= {}
      merged_kwargs = @kwargs.merge(meta_params)
      @result = @klass.build_type(*@args, sv_params: @sv_param_overrides, **merged_kwargs)
      @result
    end
  end

  # Base class for defining SV struct (typedef struct packed).
  #
  # Example:
  #   class MyBundle < RSV::BundleDef
  #     def build(width: 8)
  #       valid = field("valid", bit)
  #       data  = field("data",  uint(width))
  #     end
  #   end
  #
  #   dat_t = MyBundle.new
  #   r = reg("my_reg", dat_t)
  class BundleDef
    attr_reader :fields, :params, :type_name

    class << self
      def new(*args, **kwargs)
        raise ArgumentError, "BundleDef must be subclassed" if self == RSV::BundleDef

        if sv_param_defs.any?
          return CurriedBundleBuilder.new(self, *args, **kwargs)
        end

        build_type(*args, **kwargs)
      end

      def build_type(*args, sv_params: {}, **kwargs)
        bundle = allocate
        bundle.instance_variable_set(:@_sv_param_overrides, sv_params)
        bundle.send(:initialize, *args, **kwargs)
        bundle.send(:finalize_type_name!)
        bundle.send(:to_data_type)
      end

      def sv_param(name, default_value)
        sv_param_defs << { name: name.to_s, default: default_value }
        SvParamRef.new(name.to_s)
      end

      def sv_param_defs
        @sv_param_defs ||= []
      end

      def bundle_def_instance
        @bundle_def_instance
      end

      private

      def resolve_registered_type_name(base_name, sv_signature)
        variants = type_variant_registry[base_name]
        existing = variants.find { |entry| entry[:sv_signature] == sv_signature }
        return existing[:type_name] if existing

        type_name = variants.empty? ? base_name : "#{base_name}_#{variants.length}"
        variants << { type_name: type_name, sv_signature: sv_signature }
        type_name
      end

      def type_variant_registry
        @type_variant_registry ||= Hash.new { |hash, key| hash[key] = [] }
      end
    end

    def initialize(*args, **kwargs)
      @fields = []
      @params = []
      @type_name = nil
      @type_name_finalized = false

      apply_sv_param_defs

      auto_build = self.class.instance_method(:initialize).owner == BundleDef &&
        self.class.instance_method(:build).owner != BundleDef
      build(*args, **kwargs) if auto_build

      resolve_sv_param_refs!
    end

    def build(*args, **kwargs)
    end

    # Type constructors (same as ModuleDef)
    def bit(init = nil, **kwargs)
      init = kwargs[:init] if kwargs.key?(:init)
      DataType.new(width: 1, init: init)
    end

    def bits(width = 1, init = nil, **kwargs)
      width = kwargs[:width] if kwargs.key?(:width)
      init = kwargs[:init] if kwargs.key?(:init)
      DataType.new(width: width, signed: false, init: init)
    end

    def uint(width = 1, init = nil, signed: false, **kwargs)
      width = kwargs[:width] if kwargs.key?(:width)
      init = kwargs[:init] if kwargs.key?(:init)
      DataType.new(width: width, signed: signed, init: init)
    end

    def sint(width = 1, init = nil, **kwargs)
      width = kwargs[:width] if kwargs.key?(:width)
      init = kwargs[:init] if kwargs.key?(:init)
      DataType.new(width: width, signed: true, init: init)
    end

    def arr(*dims_and_target)
      compose_data_type(*dims_and_target, storage: :packed)
    end

    def mem(*dims_and_target)
      compose_data_type(*dims_and_target, storage: :unpacked)
    end

    def field(name, data_type)
      type = RSV.normalize_data_type(data_type)
      @fields << BundleFieldDef.new(name: name.to_s, data_type: type)
      @fields.last
    end

    private

    def apply_sv_param_defs
      overrides = @_sv_param_overrides || {}
      self.class.sv_param_defs.each do |pd|
        key_sym = pd[:name].to_sym
        key_str = pd[:name].to_s
        value = overrides.fetch(key_sym, overrides.fetch(key_str, pd[:default]))
        type = infer_sv_param_type(value)
        @params << ParamDecl.new(pd[:name], value, type)
      end
    end

    def infer_sv_param_type(value)
      case value
      when Integer then "int"
      when String then "string"
      else "int"
      end
    end

    def resolve_sv_param_refs!
      return if @params.empty?

      param_map = {}
      @params.each { |p| param_map[p.name] = p.value }

      @fields.map! do |f|
        dt = f.data_type
        new_width = resolve_param_value(dt.width, param_map)
        new_packed = dt.packed_dims.map { |d| resolve_param_value(d, param_map) }
        new_unpacked = dt.unpacked_dims.map { |d| resolve_param_value(d, param_map) }
        if new_width != dt.width || new_packed != dt.packed_dims || new_unpacked != dt.unpacked_dims
          new_dt = DataType.new(
            width: new_width, signed: dt.signed, init: dt.init,
            packed_dims: new_packed, unpacked_dims: new_unpacked,
            bundle_type: dt.bundle_type
          )
          BundleFieldDef.new(name: f.name, data_type: new_dt)
        else
          f
        end
      end
    end

    def resolve_param_value(val, param_map)
      case val
      when SvParamRef
        param_map.fetch(val.name, val)
      else
        val
      end
    end

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
      # Convert PascalCase to snake_case and append _t
      n.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase + "_t"
    end

    def render_typedef(type_name:)
      lines = []
      lines << "typedef struct packed {"
      @fields.each do |f|
        dt = f.data_type
        if dt.bundle_type
          dim_str = ""
          dt.packed_dims.each { |d| dim_str += "[#{RSV.format_dim(d)}]" }
          dt.unpacked_dims.each { |d| dim_str += "[#{RSV.format_dim(d)}]" }
          lines << "  #{dt.bundle_type.type_name} #{f.name}#{dim_str};"
        else
          lines << "  #{Emitter.format_field_decl(f)};"
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

      total = base
      dt.packed_dims.each do |d|
        return 0 unless d.is_a?(Integer)
        total *= d
      end
      total
    end

    def compose_data_type(*dims_and_target, storage:)
      raise ArgumentError, "arr/mem expects dimensions + type" if dims_and_target.length < 2

      target = RSV.normalize_data_type(dims_and_target[-1])
      dims = dims_and_target[0...-1]
      dims = dims.first if dims.length == 1 && dims.first.is_a?(Array)
      dims = Array(dims).flatten.map { |d| RSV.normalize_expr(d) }

      case storage
      when :packed
        target.append_dimensions(packed: dims)
      when :unpacked
        target.append_dimensions(unpacked: dims)
      end
    end
  end
end
