# frozen_string_literal: true

require "fileutils"

module RSV
  # Curried builder for interfaces with sv_param declarations.
  class CurriedInterfaceBuilder < CurriedBuilderBase
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
  # Declare signals with input/output (from the master's perspective).
  # Modports "mst" and "slv" are auto-generated.
  #
  # Example:
  #   class AXILite < RSV::InterfaceDef
  #     def build(addr_w: 32, data_w: 32)
  #       awaddr  = output("awaddr",  uint(addr_w))
  #       awvalid = output("awvalid", bit)
  #       awready = input("awready",  bit)
  #       wdata   = output("wdata",   uint(data_w))
  #     end
  #   end
  #
  #   # In a module:
  #   bus = intf("bus", AXILite.new(addr_w: 16).slv)
  class InterfaceDef
    include TypeConstructors
    include SvParamSupport
    include TypeVariantRegistry

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
    end

    def initialize(*args, **kwargs)
      @fields = []
      @params = []
      @type_name = nil
      @type_name_finalized = false

      apply_sv_param_defs

      auto_build = self.class.instance_method(:initialize).owner == InterfaceDef &&
        self.class.instance_method(:build).owner != InterfaceDef
      build(*args, **kwargs) if auto_build

      resolve_sv_param_refs!
      synthesize_modports!
    end

    def build(*args, **kwargs)
    end

    # Declare an output signal (from the master's perspective).
    def output(name, data_type)
      dt = RSV.normalize_data_type(data_type)
      @fields << { name: name.to_s, dir: "output", data_type: dt }
      @fields.last
    end

    # Declare an input signal (from the master's perspective).
    def input(name, data_type)
      dt = RSV.normalize_data_type(data_type)
      @fields << { name: name.to_s, dir: "input", data_type: dt }
      @fields.last
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

    # Auto-generate "mst" (as-declared) and "slv" (reversed) modports.
    def synthesize_modports!
      @modports = []
      mst_ports = @fields.map { |f| { name: f[:name], dir: f[:dir] } }
      slv_ports = @fields.map { |f| { name: f[:name], dir: flip_dir(f[:dir]) } }
      @modports << { name: "mst", ports: mst_ports }
      @modports << { name: "slv", ports: slv_ports }
    end

    def flip_dir(dir)
      dir == "output" ? "input" : "output"
    end

    # Resolve SvParamRef values in field widths/dims after build.
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
      dt.instance_variable_set(:@_intf_modport, "mst")
      dt
    end
  end
end
