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

  # ── Handler delegation via metaprogramming ───────────────────────────────
  # Reduces boilerplate for ClockSignal / ResetSignal delegate methods.
  module HandlerDelegation
    DELEGATED_METHODS = %i[
      name width signed kind init
      unpacked_dims base_name
      to_s element_width
    ].freeze

    def self.included(base)
      DELEGATED_METHODS.each do |m|
        base.define_method(m) { @handler.send(m) }
      end
    end
  end
end
