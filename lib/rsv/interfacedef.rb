# frozen_string_literal: true

module RSV
  # Curried builder for interfaces with sv_param declarations.
  class CurriedInterfaceBuilder
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

  # Base class for defining SV interfaces.
  #
  # Example:
  #   class AXILite < RSV::InterfaceDef
  #     def build(addr_w: 32, data_w: 32)
  #       awaddr  = field("awaddr",  :input,  uint(addr_w))
  #       awvalid = field("awvalid", :input,  bit)
  #       awready = field("awready", :output, bit)
  #       wdata   = field("wdata",   :input,  uint(data_w))
  #       modport "master", inputs: [awaddr, awvalid, wdata], outputs: [awready]
  #       modport "slave",  inputs: [awready], outputs: [awaddr, awvalid, wdata]
  #     end
  #   end
  class InterfaceDef
    attr_reader :fields, :params, :modports, :type_name

    class << self
      def new(*args, **kwargs)
        raise ArgumentError, "InterfaceDef must be subclassed" if self == RSV::InterfaceDef

        if sv_param_defs.any?
          return CurriedInterfaceBuilder.new(self, *args, **kwargs)
        end

        build_type(*args, **kwargs)
      end

      def build_type(*args, sv_params: {}, **kwargs)
        intf = allocate
        intf.instance_variable_set(:@_sv_param_overrides, sv_params)
        intf.send(:initialize, *args, **kwargs)
        intf.send(:finalize_type_name!)
        intf.send(:to_data_type)
      end

      def sv_param(name, default_value)
        sv_param_defs << { name: name.to_s, default: default_value }
        SvParamRef.new(name.to_s)
      end

      def sv_param_defs
        @sv_param_defs ||= []
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
      @modports = []
      @type_name = nil
      @type_name_finalized = false

      apply_sv_param_defs

      auto_build = self.class.instance_method(:initialize).owner == InterfaceDef &&
        self.class.instance_method(:build).owner != InterfaceDef
      build(*args, **kwargs) if auto_build

      resolve_sv_param_refs!
    end

    def build(*args, **kwargs)
    end

    # Type constructors
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

    # Declare an interface signal with optional direction.
    # dir can be nil (for logic without direction), :input, or :output.
    # Returns the field hash for use as a handle.
    def field(name, dir_or_type = nil, data_type = nil)
      if data_type.nil?
        dt = RSV.normalize_data_type(dir_or_type)
        @fields << { name: name.to_s, dir: nil, data_type: dt }
      else
        dt = RSV.normalize_data_type(data_type)
        @fields << { name: name.to_s, dir: dir_or_type.to_s, data_type: dt }
      end
      @fields.last
    end

    # Define a modport.
    # Accepts field handles or strings for inputs/outputs.
    def modport(name, inputs: [], outputs: [])
      ports = inputs.map { |n| { name: field_name_of(n), dir: "input" } } +
              outputs.map { |n| { name: field_name_of(n), dir: "output" } }
      @modports << { name: name.to_s, ports: ports }
    end

    def to_sv(output = nil)
      finalize_type_name!
      sv = render_interface
      if output
        dir = File.dirname(output)
        FileUtils.mkdir_p(dir) unless dir.empty?
        File.write(output, sv)
      end
      sv
    end

    private

    def field_name_of(ref)
      case ref
      when Hash then ref[:name]
      when RSV::BundleFieldDef then ref.name
      else ref.to_s
      end
    end

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
        dt = f[:data_type]
        new_width = resolve_param_value(dt.width, param_map)
        new_packed = dt.packed_dims.map { |d| resolve_param_value(d, param_map) }
        new_unpacked = dt.unpacked_dims.map { |d| resolve_param_value(d, param_map) }
        if new_width != dt.width || new_packed != dt.packed_dims || new_unpacked != dt.unpacked_dims
          new_dt = DataType.new(
            width: new_width, signed: dt.signed, init: dt.init,
            packed_dims: new_packed, unpacked_dims: new_unpacked,
            bundle_type: dt.bundle_type
          )
          f.merge(data_type: new_dt)
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
      sv_sig = render_interface
      @type_name = self.class.send(:resolve_registered_type_name, base_name, sv_sig)
      @type_name_finalized = true
      @type_name
    end

    def default_type_name
      n = self.class.name.to_s.split("::").last
      n.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
    end

    def render_interface
      emitter = Emitter.new
      elab = ElaboratedInterface.new(
        @type_name || "__rsv_canonical_intf__",
        params: @params,
        fields: @fields,
        modports: @modports
      )
      emitter.emit_interface(elab)
    end

    def to_data_type
      dt = DataType.new(width: 1, signed: false)
      dt.instance_variable_set(:@_intf_def, self)
      dt
    end
  end
end
