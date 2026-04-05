# frozen_string_literal: true

module RSV
  # ── Shared type constructor methods ──────────────────────────────────────
  # Included by ModuleDef and BundleDef.
  module TypeConstructors
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
  end

  # ── Shared sv_param support ──────────────────────────────────────────────
  # Class-level and instance-level helpers for SV parameter handling.
  # Include in BundleDef, ModuleDef.
  module SvParamSupport
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def sv_param(name, default_value)
        sv_param_defs << { name: name.to_s, default: default_value }
        SvParamRef.new(name.to_s)
      end

      def sv_param_defs
        @sv_param_defs ||= []
      end
    end

    private

    # Apply sv_param defaults / overrides into @params.
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

    def resolve_param_value(val, param_map)
      case val
      when SvParamRef then param_map.fetch(val.name, val)
      else val
      end
    end
  end

  # ── Shared type variant dedup registry ───────────────────────────────────
  # Class-level helper that tracks generated type names per SV signature,
  # ensuring unique names when meta_params produce different SV output.
  module TypeVariantRegistry
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
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
  end

  # ── Shared curried builder base ──────────────────────────────────────────
  # Subclass and implement #finalize(**meta_params) to produce a result.
  class CurriedBuilderBase
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
      raise NotImplementedError, "subclass must implement #finalize"
    end
  end

  # ── Handler delegation via metaprogramming ───────────────────────────────
  # Reduces boilerplate for ClockSignal / ResetSignal delegate methods.
  module HandlerDelegation
    DELEGATED_METHODS = %i[
      name width signed kind init
      packed_dims unpacked_dims base_name
      to_s element_width
    ].freeze

    def self.included(base)
      DELEGATED_METHODS.each do |m|
        base.define_method(m) { @handler.send(m) }
      end
    end
  end
end
