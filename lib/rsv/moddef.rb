# frozen_string_literal: true

require "fileutils"

module RSV
  # Builder for chaining sv_elif_def / sv_else_def onto an sv_ifdef/sv_ifndef.
  class MacroCondBuilder
    def initialize(node, mod)
      @node = node
      @mod = mod
    end

    def sv_elif_def(name, &block)
      body = @mod.send(:capture_macro_body, &block)
      @node.elsif_clauses << { macro_name: name.to_s, body: body }
      self
    end

    def sv_else_def(&block)
      body = @mod.send(:capture_macro_body, &block)
      @node.else_body = body
      self
    end
  end

  # Builder for capturing locals and statements inside a generate block.
  class GenerateBuilder
    attr_reader :locals, :stmts

    def initialize(mod)
      @mod = mod
      @locals = []
      @stmts = []
    end

    def capture(&block)
      saved_locals = @mod.instance_variable_get(:@locals)
      saved_stmts = @mod.instance_variable_get(:@stmts)
      @mod.instance_variable_set(:@locals, @locals)
      @mod.instance_variable_set(:@stmts, @stmts)
      @mod.instance_eval(&block)
      @locals = @mod.instance_variable_get(:@locals)
      @stmts = @mod.instance_variable_get(:@stmts)
      @mod.instance_variable_set(:@locals, saved_locals)
      @mod.instance_variable_set(:@stmts, saved_stmts)
    end
  end

  # Chaining helper for generate_if elsif/else
  class GenerateIfCondBuilder
    def initialize(node, mod)
      @node = node
      @mod = mod
    end

    def generate_elif(cond, label: nil, &block)
      builder = GenerateBuilder.new(@mod)
      builder.capture(&block)
      @node.add_elsif(RSV.normalize_expr(cond), label: label, locals: builder.locals, stmts: builder.stmts)
      self
    end

    def generate_else(label: nil, &block)
      builder = GenerateBuilder.new(@mod)
      builder.capture(&block)
      @node.set_else(label: label, locals: builder.locals, stmts: builder.stmts)
      self
    end
  end

  # Base class for class-based module definitions.
  #
  # Example:
  #   class Counter < RSV::ModuleDef
  #     def build(width: 8)
  #       clk = input("clk", bit)
  #       rst = input("rst", bit)
  #       out = output("count", uint(width))
  #       count_r = reg("count_r", uint(width), init: 0)
  #       out <= count_r
  #       with_clk_and_rst(clk, rst)
  #       always_ff do
  #         svif(1) do
  #           count_r <= count_r + 1
  #         end
  #       end
  #     end
  #   end
  #
  #   top = Counter.new
  #   puts top.to_sv
  class ModuleDef
    UNSET_INIT = Object.new
    PortEndpoint = Struct.new(:port_handler, :ops) do
      def whole_port?
        ops.empty?
      end

      def dir
        port_handler.dir
      end

      def inst_name
        port_handler.instance_handle.inst_name
      end

      def port_name
        port_handler.name
      end
    end

    attr_reader :params, :ports, :locals, :stmts

    class << self
      def new(*args, **kwargs, &block)
        raise ArgumentError, "ModuleDef must be subclassed" if self == RSV::ModuleDef

        current_module = RSV.current_module_def
        return current_module.send(:instantiate_module, self, *args, **kwargs) if current_module

        build_definition(*args, **kwargs, &block)
      end

      def build_definition(*args, **kwargs, &block)
        mod = allocate
        RSV.with_module_def(mod) do
          mod.send(:initialize, *args, **kwargs, &block)
        end
        mod.send(:finalize_module_name!)
        mod
      end

      def definition(*args, **kwargs, &block)
        definition = build_definition(*args, **kwargs, &block)
        definition_handle_registry[definition.module_name] ||= ModuleDefinitionHandle.new(definition)
      end

      private

      def resolve_registered_module_name(base_name, sv_signature)
        variants = module_variant_registry[base_name]
        existing = variants.find { |entry| entry[:sv_signature] == sv_signature }
        return existing[:module_name] if existing

        module_name = variants.empty? ? base_name : "#{base_name}_#{variants.length}"
        variants << { module_name: module_name, sv_signature: sv_signature }
        module_name
      end

      def module_variant_registry
        @module_variant_registry ||= Hash.new { |hash, key| hash[key] = [] }
      end

      def definition_handle_registry
        @definition_handle_registry ||= {}
      end
    end

    def initialize(name = nil, *args, **kwargs)
      @name = normalize_module_name(name || default_module_name)
      @params = []
      @ports = []
      @locals = []
      @stmts = []
      @current_clock = nil
      @current_reset = nil
      @instance_counts = Hash.new(0)
      @module_name_finalized = false
      @auto_connection_wires = {}
      @instance_port_base_wires = {}

      auto_build = self.class.instance_method(:initialize).owner == ModuleDef &&
        self.class.instance_method(:build).owner != ModuleDef
      build(*args, **kwargs) if auto_build
    end

    def module_name
      @name
    end

    alias name module_name

    def module_name=(value)
      @name = normalize_module_name(value)
      @module_name_finalized = false
    end

    def build(*args, **kwargs)
    end

    def definition(source, *args, **kwargs, &block)
      build_definition_handle(source, *args, **kwargs, &block)
    end

    def instance(module_definition, inst_name: nil)
      instantiate_definition_handle(
        RSV.normalize_module_definition_handle(module_definition),
        inst_name: inst_name
      )
    end

    # ── Port declarations ───────────────────────────────────────────────────

    include TypeConstructors

    def clock(init = nil, **kwargs)
      init = kwargs[:init] if kwargs.key?(:init)
      DataType.new(width: 1, init: init, packed_dims: [], unpacked_dims: []).tap do |dt|
        dt.instance_variable_set(:@_clock_type, true)
      end
    end

    def reset(init = nil, **kwargs)
      init = kwargs[:init] if kwargs.key?(:init)
      DataType.new(width: 1, init: init, packed_dims: [], unpacked_dims: []).tap do |dt|
        dt.instance_variable_set(:@_reset_type, true)
      end
    end

    # Direction decorator: wraps a data type with :input direction.
    # When given (name, type), declares an input port directly (for clock/reset convenience).
    def input(name_or_type, data_type = nil, init: UNSET_INIT, attr: nil)
      if data_type.nil?
        # Direction decorator mode: input(uint(8)) → DirectedType
        type = name_or_type
        type = RSV.normalize_data_type(type) if type.is_a?(DataType)
        return DirectedType.new(:input, type)
      end
      # Legacy-compatible direct port declaration: input("clk", clock)
      clock_type = data_type.instance_variable_get(:@_clock_type) || false
      reset_type = data_type.instance_variable_get(:@_reset_type) || false
      declare_port(:input, build_signal_spec(name_or_type, data_type, init: init), clock_type: clock_type, reset_type: reset_type, attr: attr)
    end

    # Direction decorator: wraps a data type with :output direction.
    # When given (name, type), declares an output port directly (for clock/reset convenience).
    def output(name_or_type, data_type = nil, init: UNSET_INIT, attr: nil)
      if data_type.nil?
        type = name_or_type
        type = RSV.normalize_data_type(type) if type.is_a?(DataType)
        return DirectedType.new(:output, type)
      end
      clock_type = data_type.instance_variable_get(:@_clock_type) || false
      reset_type = data_type.instance_variable_get(:@_reset_type) || false
      declare_port(:output, build_signal_spec(name_or_type, data_type, init: init), clock_type: clock_type, reset_type: reset_type, attr: attr)
    end

    def inout(name_or_type, data_type = nil, init: UNSET_INIT, attr: nil)
      if data_type.nil?
        type = name_or_type
        type = RSV.normalize_data_type(type) if type.is_a?(DataType)
        return DirectedType.new(:inout, type)
      end
      clock_type = data_type.instance_variable_get(:@_clock_type) || false
      reset_type = data_type.instance_variable_get(:@_reset_type) || false
      declare_port(:inout, build_signal_spec(name_or_type, data_type, init: init), clock_type: clock_type, reset_type: reset_type, attr: attr)
    end

    # Flip bundle direction: all input fields become output and vice versa.
    def flip(data_type)
      dt = data_type.is_a?(DataType) ? data_type : RSV.normalize_data_type(data_type)
      FlippedType.new(dt)
    end

    # IO port declaration: expand directed types / bundles into module ports.
    def iodecl(name, directed_type, init: UNSET_INIT, attr: nil)
      case directed_type
      when DirectedType
        inner = directed_type.data_type
        dir = directed_type.dir
        if inner.is_a?(DataType) && inner.bundle_type
          spec = build_signal_spec(name, inner, init: init)
          flatten_bundle_iodecl(dir, spec, flipped: false, attr: attr)
        else
          dt = inner.is_a?(DataType) ? inner : RSV.normalize_data_type(inner)
          clock_type = dt.instance_variable_get(:@_clock_type) || false
          reset_type = dt.instance_variable_get(:@_reset_type) || false
          declare_port(dir, build_signal_spec(name, dt, init: init), clock_type: clock_type, reset_type: reset_type, attr: attr)
        end
      when FlippedType
        inner = directed_type.data_type
        raise ArgumentError, "flip() requires a bundle type" unless inner.is_a?(DataType) && inner.bundle_type
        spec = build_signal_spec(name, inner, init: init)
        flatten_bundle_iodecl(:input, spec, flipped: true, attr: attr)
      when DataType
        if directed_type.bundle_type
          spec = build_signal_spec(name, directed_type, init: init)
          flatten_bundle_iodecl(:input, spec, flipped: false, attr: attr)
        else
          raise ArgumentError, "iodecl requires a directed type (use input()/output()/flip())"
        end
      else
        raise ArgumentError, "iodecl expects a directed type, got #{directed_type.class}"
      end
    end

    # ── Internal signal declarations ────────────────────────────────────────

    def wire(name, data_type, init: UNSET_INIT, attr: nil)
      clock_type = data_type.instance_variable_get(:@_clock_type) || false
      reset_type = data_type.instance_variable_get(:@_reset_type) || false
      declare_local(:wire, build_signal_spec(name, data_type, init: init), clock_type: clock_type, reset_type: reset_type, attr: attr)
    end

    def reg(name, data_type, init: UNSET_INIT, attr: nil)
      clock_type = data_type.instance_variable_get(:@_clock_type) || false
      reset_type = data_type.instance_variable_get(:@_reset_type) || false
      declare_local(:reg, build_signal_spec(name, data_type, init: init), clock_type: clock_type, reset_type: reset_type, attr: attr)
    end

    def const(name, data_type, attr: nil)
      spec = build_signal_spec(name, data_type, init: data_type.init)
      raise ArgumentError, "const requires an init value" if spec.init.nil?

      @locals << ConstDecl.new(spec, init: spec.init, attr: attr)
      build_handler(spec, :wire)
    end

    def expr(name, rhs, width: nil, signed: false)
      rhs_expr = RSV.normalize_expr(rhs)
      inferred_width = width || RSV.infer_expr_width(rhs_expr)
      raise ArgumentError, "cannot infer width for expr #{name}" if inferred_width.nil?

      handler = declare_local(:wire, SignalSpec.new(name, width: inferred_width, signed: signed))
      append_assignment(handler, rhs_expr)
      handler
    end

    def arr(*dims_and_target)
      return DataTypeFactory.new(self, :packed) if dims_and_target.empty?

      compose_data_type(*dims_and_target, storage: :packed)
    end

    def mem(*dims_and_target)
      return DataTypeFactory.new(self, :unpacked) if dims_and_target.empty?

      compose_data_type(*dims_and_target, storage: :unpacked)
    end

    def mux(sel, a, b)
      MuxExpr.new(sel, a, b)
    end

    def cat(*parts)
      CatExpr.new(parts)
    end

    def fill(n, part)
      FillExpr.new(n, part)
    end

    def mux1h(sel1h, dats)
      Mux1hExpr.new(sel1h, dats)
    end

    def muxp(sel, dats, lsb_first: true)
      MuxpExpr.new(sel, dats, lsb_first: lsb_first)
    end

    def pop_count(vec)
      PopCountExpr.new(vec)
    end

    def log2ceil(n)
      RSV.log2ceil(n)
    end

    # ── Generate blocks ────────────────────────────────────────────────────

    def generate_if(cond, label: nil, &block)
      builder = GenerateBuilder.new(self)
      builder.capture(&block)
      node = GenerateIf.new(RSV.normalize_expr(cond), label: label, locals: builder.locals, stmts: builder.stmts)
      @stmts << node
      GenerateIfCondBuilder.new(node, self)
    end

    def generate_for(genvar_name, start_val, end_val, label: nil, &block)
      genvar = GenvarRef.new(genvar_name.to_s)
      builder = GenerateBuilder.new(self)
      builder.capture { instance_exec(genvar, &block) }
      @stmts << GenerateFor.new(
        genvar.name, start_val, end_val,
        label: label, locals: builder.locals, stmts: builder.stmts
      )
      genvar
    end

    # ── Preprocessor macros ──────────────────────────────────────────────────

    def sv_def(name, value = nil)
      @stmts << SvDefine.new(name.to_s, value&.to_s)
    end

    def sv_undef(name)
      @stmts << SvUndef.new(name.to_s)
    end

    def sv_plugin(code)
      @stmts << SvPlugin.new(code.to_s)
    end

    def sv_ifdef(name, &block)
      body = capture_macro_body(&block)
      node = SvIfdef.new(name.to_s, body, [], nil)
      @stmts << node
      MacroCondBuilder.new(node, self)
    end

    def sv_ifndef(name, &block)
      body = capture_macro_body(&block)
      node = SvIfndef.new(name.to_s, body, [], nil)
      @stmts << node
      MacroCondBuilder.new(node, self)
    end

    def sv_dref(name)
      MacroRef.new(name.to_s)
    end

    # ── Statements ───────────────────────────────────────────────────────────

    def with_clk_and_rst(clock, reset)
      @current_clock = clock.is_a?(ClockSignal) ? clock : RSV.normalize_expr(clock)
      @current_reset = reset.is_a?(ResetSignal) ? reset : RSV.normalize_expr(reset)
      self
    end

    def always_ff(clock = nil, reset = nil, &block)
      builder = ProceduralBuilder.new(assign_context: :always_ff).build(&block)

      domain_clock, domain_reset = resolve_always_ff_domain(clock, reset)
      @stmts << AlwaysFF.new(builder.stmts, clock: domain_clock, reset: domain_reset)
    end

    def always_comb(&block)
      builder = ProceduralBuilder.new(assign_context: :always_comb).build(&block)
      @stmts << AlwaysComb.new(builder.stmts)
    end

    def always_latch(&block)
      builder = ProceduralBuilder.new(assign_context: :always_latch).build(&block)
      @stmts << AlwaysLatch.new(builder.stmts)
    end

    # ── Output ───────────────────────────────────────────────────────────────

    def to_sv(output = nil)
      finalize_module_name!
      sv = render_sv(module_name: @name)
      write_sv_output(sv, output)
      sv
    end

    def v_wrapper(output = nil, wrapper_name: nil)
      finalize_module_name!
      wrapper_name ||= "#{@name}_wrapper"
      verilog = VerilogWrapperGenerator.new.generate(self, wrapper_name)
      write_sv_output(verilog, output)
      verilog
    end

    private

    def capture_macro_body(&block)
      saved_stmts = @stmts
      @stmts = []
      instance_eval(&block)
      body = @stmts
      @stmts = saved_stmts
      body
    end

    def compose_data_type(*dims_and_target, storage:)
      dims, data_type = extract_dims_and_data_type(dims_and_target, storage)
      normalized_dims = normalize_decl_dimensions(dims)

      # Flatten nested same-storage dimensions from inner DataType
      case storage
      when :packed
        inner_packed = data_type.packed_dims.dup
        data_type = DataType.new(
          width: data_type.width,
          signed: data_type.signed,
          init: data_type.init,
          packed_dims: [],
          unpacked_dims: data_type.unpacked_dims,
          bundle_type: data_type.bundle_type
        )
        data_type.append_dimensions(packed: normalized_dims + inner_packed)
      when :unpacked
        inner_unpacked = data_type.unpacked_dims.dup
        data_type = DataType.new(
          width: data_type.width,
          signed: data_type.signed,
          init: data_type.init,
          packed_dims: data_type.packed_dims,
          unpacked_dims: [],
          bundle_type: data_type.bundle_type
        )
        data_type.append_dimensions(unpacked: normalized_dims + inner_unpacked)
      else
        raise ArgumentError, "unknown storage kind #{storage}"
      end
    end

    def extract_dims_and_data_type(args, storage)
      raise ArgumentError, "#{storage == :packed ? 'arr' : 'mem'} expects one or more dimensions and a data type" if args.length < 2

      target = RSV.normalize_data_type(args[-1])
      dims = args[0...-1]
      dims = dims.first if dims.length == 1 && dims.first.is_a?(Array)
      dims = Array(dims)
      raise ArgumentError, "#{storage == :packed ? 'arr' : 'mem'} expects at least one dimension" if dims.empty?

      [dims, target]
    end

    def normalize_decl_dimensions(dims)
      dims.flatten.map { |dim| RSV.normalize_expr(dim) }
    end

    def build_signal_spec(name, data_type, init:)
      raise TypeError, "hardware declarations expect a signal name String, got #{name.class}" unless name.is_a?(String)

      type = RSV.normalize_data_type(data_type)
      effective_init = init.equal?(UNSET_INIT) ? type.init : init

      # Allow Hash init for bundle types (partial field initialization)
      if effective_init.is_a?(Hash) && type.bundle_type
        # validate field names
        valid_fields = type.bundle_type.fields.map(&:name)
        effective_init.each_key do |k|
          raise ArgumentError, "unknown bundle field '#{k}' in init for #{name}" unless valid_fields.include?(k.to_s)
        end
      elsif effective_init.is_a?(DataType) && !RSV.shape_matches_type?(type, effective_init)
        raise ArgumentError, "initializer shape must match declared data type for #{name}"
      end

      SignalSpec.new(
        name,
        width: type.width,
        signed: type.signed,
        init: effective_init,
        packed_dims: type.packed_dims,
        unpacked_dims: type.unpacked_dims,
        bundle_type: type.bundle_type
      )
    end

    def declare_port(dir, spec, clock_type: false, reset_type: false, attr: nil)
      raise ArgumentError, "#{dir} does not support init" unless spec.init.nil?
      raise ArgumentError, "Bundle types must use iodecl() for port declarations" if spec.bundle_type

      @ports << PortDecl.new(dir, spec, attr: attr)
      handler = build_handler(spec, dir)
      return ClockSignal.new(handler) if clock_type
      return ResetSignal.new(handler) if reset_type

      handler
    end

    def declare_local(kind, spec, clock_type: false, reset_type: false, attr: nil)
      if spec.bundle_type
        return flatten_bundle_local(kind, spec, attr: attr)
      end

      @locals << build_local_decl(kind, spec, attr: attr)
      handler = build_handler(spec, kind)
      return ClockSignal.new(handler) if clock_type
      return ResetSignal.new(handler) if reset_type

      handler
    end

    # Direction-aware bundle port expansion for iodecl().
    # Each field's direction comes from the BundleFieldDef.dir,
    # optionally flipped.
    def flatten_bundle_iodecl(base_dir, spec, flipped: false, attr: nil)
      children = {}
      spec.bundle_type.fields.each do |f|
        child_name = "#{spec.name}_#{f.name}"
        dt = f.data_type
        field_dir = resolve_field_dir(f.dir, flipped)
        if dt.bundle_type
          child_spec = SignalSpec.new(
            child_name,
            width: dt.width, signed: dt.signed,
            packed_dims: dt.packed_dims,
            unpacked_dims: spec.unpacked_dims + dt.unpacked_dims,
            bundle_type: dt.bundle_type
          )
          children[f.name] = flatten_bundle_iodecl(field_dir, child_spec, flipped: flipped, attr: attr)
        else
          child_spec = SignalSpec.new(
            child_name,
            width: dt.width, signed: dt.signed,
            packed_dims: dt.packed_dims,
            unpacked_dims: spec.unpacked_dims + dt.unpacked_dims
          )
          @ports << PortDecl.new(field_dir, child_spec, attr: attr)
          children[f.name] = build_handler(child_spec, field_dir)
        end
      end
      BundleSignalGroup.new(
        spec.name,
        bundle_type: spec.bundle_type,
        children: children,
        unpacked_dims: spec.unpacked_dims
      )
    end

    def resolve_field_dir(field_dir, flipped)
      return field_dir unless flipped
      case field_dir
      when :input then :output
      when :output then :input
      else field_dir
      end
    end

    def flatten_bundle_local(kind, spec, attr: nil)
      children = {}
      init_hash = spec.init.is_a?(Hash) ? spec.init : nil
      spec.bundle_type.fields.each do |f|
        child_name = "#{spec.name}_#{f.name}"
        dt = f.data_type
        field_init = init_hash ? init_hash[f.name] || init_hash[f.name.to_sym] : nil
        if dt.bundle_type
          child_spec = SignalSpec.new(
            child_name,
            width: dt.width, signed: dt.signed, init: field_init,
            packed_dims: dt.packed_dims,
            unpacked_dims: spec.unpacked_dims + dt.unpacked_dims,
            bundle_type: dt.bundle_type
          )
          children[f.name] = flatten_bundle_local(kind, child_spec, attr: attr)
        else
          child_init = field_init || (spec.init.is_a?(Hash) ? nil : nil)
          child_spec = SignalSpec.new(
            child_name,
            width: dt.width, signed: dt.signed, init: child_init,
            packed_dims: dt.packed_dims,
            unpacked_dims: spec.unpacked_dims + dt.unpacked_dims
          )
          @locals << build_local_decl(kind, child_spec, attr: attr)
          children[f.name] = build_handler(child_spec, kind)
        end
      end
      BundleSignalGroup.new(
        spec.name,
        bundle_type: spec.bundle_type,
        children: children,
        unpacked_dims: spec.unpacked_dims
      )
    end

    def build_local_decl(kind, spec, attr: nil)
      case kind
      when :reg
        LocalDecl.new(kind, spec, init: nil, reset_init: spec.init, attr: attr)
      else
        LocalDecl.new(kind, spec, attr: attr)
      end
    end

    def build_handler(spec, kind)
      SignalHandler.new(
        spec.name,
        width: spec.width,
        signed: spec.signed,
        kind: kind,
        init: spec.init,
        packed_dims: spec.packed_dims,
        unpacked_dims: spec.unpacked_dims,
        bundle_type: spec.bundle_type
      )
    end

    def resolve_always_ff_domain(clock, reset)
      if clock.nil? && reset.nil?
        raise "with_clk_and_rst must be set before always_ff" unless @current_clock && @current_reset

        return [@current_clock, @current_reset]
      end

      raise ArgumentError, "always_ff expects no arguments or explicit clock/reset" if clock.nil? || reset.nil?

      [RSV.normalize_expr(clock), RSV.normalize_expr(reset)]
    end

    def instantiate_module(module_class, *args, **kwargs)
      inst_name = kwargs.delete(:inst_name)
      definition_handle = build_definition_handle(module_class, *args, **kwargs)
      inst_name ||= next_instance_name(definition_handle)
      instantiate_definition_handle(definition_handle, inst_name: inst_name)
    end

    def build_definition_handle(source, *args, **kwargs, &block)
      return source.definition(*args, **kwargs, &block) if source.respond_to?(:build_definition) && source.respond_to?(:definition)
      raise ArgumentError, "definition handle does not accept extra arguments" unless args.empty? && kwargs.empty?

      RSV.normalize_module_definition_handle(source)
    end

    def instantiate_definition_handle(definition_handle, inst_name:, param_overrides: {})
      inst_name ||= next_instance_name(definition_handle)
      handle = ModuleInstanceHandle.new(definition_handle, inst_name: inst_name, param_overrides: param_overrides)
      @stmts << Instance.new(handle.module_name, handle.inst_name, params: handle.params, connections: handle.connections)
      handle
    end

    def next_instance_name(module_definition)
      definition_handle = RSV.normalize_module_definition_handle(module_definition)
      base_name = underscore_name(definition_handle.module_name)
      count = @instance_counts[base_name]
      @instance_counts[base_name] += 1
      count.zero? ? "u_#{base_name}" : "u_#{base_name}_#{count}"
    end

    def default_module_name
      self.class.name.to_s.split("::").last
    end

    def finalize_module_name!
      return @name if @module_name_finalized

      base_name = @name
      sv_signature = render_sv(module_name: "__rsv_canonical_module__")
      @name = self.class.send(:resolve_registered_module_name, base_name, sv_signature)
      @module_name_finalized = true
      @name
    end

    def render_sv(module_name:)
      AssignmentValidator.new.validate(self)
      lowered = Elaborator.new.elaborate(self)
      lowered = ElaboratedModule.new(module_name, params: lowered.params, ports: lowered.ports, locals: lowered.locals, stmts: lowered.stmts)
      Emitter.new.emit_module(lowered)
    end

    def normalize_module_name(value)
      raise TypeError, "module_name must be a String" unless value.is_a?(String)
      raise ArgumentError, "module_name must not be empty" if value.empty?

      value
    end

    def underscore_name(name)
      name.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
    end

    # ── Assignment & auto-connection ──────────────────────────────────────

    # Central assignment dispatcher. Routes to
    # instance port auto-wiring or plain continuous assignment.
    def append_assignment(lhs, rhs)
      lhs_port = instance_port_endpoint(lhs)
      rhs_port = instance_port_endpoint(rhs)

      if lhs_port && rhs_port
        return connect_instance_ports(lhs_port, rhs_port)
      end

      if lhs_port || rhs_port
        return connect_instance_endpoint(lhs_port || rhs_port, lhs_port ? rhs : lhs)
      end

      if rhs.is_a?(Mux1hExpr) || rhs.is_a?(MuxpExpr) || rhs.is_a?(PopCountExpr)
        wire_handler = expand_complex_rhs(rhs)
        rhs = wire_handler
      end

      stmt = AssignStmt.new(RSV.normalize_expr(lhs), RSV.normalize_expr(rhs))
      @stmts << stmt
      stmt
    end

    def instance_port_endpoint(operand)
      operand = RSV.normalize_expr(operand)

      case operand
      when InstancePortHandler
        PortEndpoint.new(operand, [])
      when IndexExpr
        endpoint = instance_port_endpoint(operand.base)
        endpoint && PortEndpoint.new(endpoint.port_handler, endpoint.ops + [{ type: :index, index: operand.index }])
      when RangeSelectExpr
        endpoint = instance_port_endpoint(operand.base)
        endpoint && PortEndpoint.new(endpoint.port_handler, endpoint.ops + [{ type: :range, msb: operand.msb, lsb: operand.lsb }])
      when IndexedPartSelectExpr
        endpoint = instance_port_endpoint(operand.base)
        endpoint && PortEndpoint.new(
          endpoint.port_handler,
          endpoint.ops + [{ type: :indexed_part, start: operand.start, direction: operand.direction, part_width: operand.part_width }]
        )
      else
        nil
      end
    rescue TypeError
      nil
    end

    def bind_endpoint_expr(endpoint, base_expr)
      endpoint.ops.reduce(base_expr) do |expr, op|
        case op[:type]
        when :index
          IndexExpr.new(expr, op[:index])
        when :range
          RangeSelectExpr.new(expr, op[:msb], op[:lsb])
        when :indexed_part
          IndexedPartSelectExpr.new(expr, op[:start], op[:direction], op[:part_width])
        else
          raise ArgumentError, "unknown endpoint op #{op[:type]}"
        end
      end
    end

    def connect_instance_ports(lhs_endpoint, rhs_endpoint)
      driver, sink = classify_instance_endpoints(lhs_endpoint, rhs_endpoint)
      interconnect = driver_signal_for(driver)

      if sink.whole_port?
        connect_instance_port(sink.port_handler, interconnect)
      else
        sink_base_wire = ensure_instance_port_base_wire(sink.port_handler)
        append_assignment(bind_endpoint_expr(sink, sink_base_wire), interconnect)
      end
    end

    def connect_instance_endpoint(endpoint, signal)
      return connect_instance_port(endpoint.port_handler, signal) if endpoint.whole_port?

      case endpoint.dir
      when :output
        append_assignment(signal, driver_signal_for(endpoint))
      when :input
        sink_base_wire = ensure_instance_port_base_wire(endpoint.port_handler)
        append_assignment(bind_endpoint_expr(endpoint, sink_base_wire), signal)
      else
        raise ArgumentError, "instance port auto-wiring only supports input/output ports"
      end
    end

    def classify_instance_endpoints(lhs_endpoint, rhs_endpoint)
      if lhs_endpoint.dir == :output && rhs_endpoint.dir == :input
        [lhs_endpoint, rhs_endpoint]
      elsif lhs_endpoint.dir == :input && rhs_endpoint.dir == :output
        [rhs_endpoint, lhs_endpoint]
      else
        raise ArgumentError, "instance port auto-wiring expects one output source and one input sink"
      end
    end

    def driver_signal_for(endpoint)
      base_wire = ensure_instance_port_base_wire(endpoint.port_handler)
      return base_wire if endpoint.whole_port?

      wire_name = endpoint_wire_name(endpoint)
      cached = @auto_connection_wires[wire_name]
      return cached if cached

      bound_expr = bind_endpoint_expr(endpoint, base_wire)
      wire = declare_auto_connection_wire(wire_name, bound_expr)
      @auto_connection_wires[wire_name] = wire
      append_assignment(wire, bound_expr)
      wire
    end

    def ensure_instance_port_base_wire(port_handler)
      key = [port_handler.instance_handle.inst_name, port_handler.name]
      cached = @instance_port_base_wires[key]
      return cached if cached

      wire = declare_auto_connection_wire(
        "#{port_handler.instance_handle.inst_name}_#{port_handler.name}",
        resolved_instance_port_signal_spec(port_handler)
      )
      connect_instance_port(port_handler, wire)
      @instance_port_base_wires[key] = wire
      wire
    end

    def declare_auto_connection_wire(name, prototype)
      return @auto_connection_wires[name] if @auto_connection_wires.key?(name)

      spec = if prototype.is_a?(SignalSpec)
        prototype
      else
        SignalSpec.new(
          name,
          width: RSV.element_width(prototype),
          signed: RSV.expr_signed(prototype),
          packed_dims: RSV.expr_packed_dims(prototype),
          unpacked_dims: RSV.expr_unpacked_dims(prototype)
        )
      end

      declare_local(:wire, spec)
    end

    def endpoint_wire_name(endpoint)
      parts = [endpoint.inst_name, endpoint.port_name]
      endpoint.ops.each do |op|
        case op[:type]
        when :index
          parts << wire_name_part(op[:index])
        when :range
          parts << wire_name_part(op[:msb]) << wire_name_part(op[:lsb])
        when :indexed_part
          parts << wire_name_part(op[:start])
          parts << (op[:direction] == :+ ? "plus" : "minus")
          parts << wire_name_part(op[:part_width])
        end
      end
      parts.join("_")
    end

    def wire_name_part(expr)
      expr = RSV.normalize_expr(expr)
      raw = case expr
      when LiteralExpr
        expr.value.to_s
      when SignalHandler, InstancePortHandler
        expr.name
      when RawExpr
        expr.source
      else
        expr.to_s
      end

      sanitized = raw.gsub(/[^A-Za-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
      sanitized.empty? ? "expr" : sanitized
    end

    # Auto-expand mux1h/muxp/pop_count into a temp wire + always_comb block.
    # Returns the wire handler to be used as a normal expression.
    def expand_complex_rhs(rhs)
      case rhs
      when PopCountExpr
        base = wire_name_part(rhs.vec)
        name = unique_auto_wire_name("#{base}_pop_count")
        w = wire(name, uint(rhs.out_width))
        stmt = PopCountStmt.new(RSV.normalize_expr(w), rhs.vec,
                                in_width: rhs.in_width, out_width: rhs.out_width)
        @stmts << AlwaysComb.new([stmt])
        w
      when Mux1hExpr
        sel_part = wire_name_part(rhs.sel)
        dat_part = mux_dats_name_part(rhs.dats)
        name = unique_auto_wire_name("#{sel_part}_mux1h_#{dat_part}")
        dt = infer_mux_data_type(rhs.dats)
        w = wire(name, dt)
        stmt = MuxCaseStmt.new(RSV.normalize_expr(w), rhs.sel, rhs.dats, case_type: :unique)
        @stmts << AlwaysComb.new([stmt])
        w
      when MuxpExpr
        sel_part = wire_name_part(rhs.sel)
        dat_part = mux_dats_name_part(rhs.dats)
        suffix = rhs.lsb_first ? "lo" : "hi"
        name = unique_auto_wire_name("#{sel_part}_muxp_#{suffix}_#{dat_part}")
        dt = infer_mux_data_type(rhs.dats)
        w = wire(name, dt)
        stmt = MuxCaseStmt.new(RSV.normalize_expr(w), rhs.sel, rhs.dats,
                               case_type: :priority, lsb_first: rhs.lsb_first)
        @stmts << AlwaysComb.new([stmt])
        w
      end
    end

    def mux_dats_name_part(dats)
      if dats.is_a?(SignalHandler)
        dats.name
      elsif dats.is_a?(Array) && !dats.empty?
        wire_name_part(dats.first)
      else
        "dats"
      end
    end

    def unique_auto_wire_name(base)
      @auto_wire_counters ||= Hash.new(0)
      count = @auto_wire_counters[base]
      @auto_wire_counters[base] += 1
      count == 0 ? base : "#{base}_#{count}"
    end

    def infer_mux_data_type(dats)
      if dats.is_a?(SignalHandler) && (!dats.unpacked_dims.empty? || !dats.packed_dims.empty?)
        w = dats.width
        s = dats.signed
      elsif dats.is_a?(Array) && !dats.empty?
        first = RSV.normalize_expr(dats.first)
        w = RSV.infer_expr_width(first)
        s = first.respond_to?(:signed) ? first.signed : false
      else
        raise ArgumentError, "cannot infer mux data type from #{dats.inspect}"
      end
      s ? sint(w) : uint(w)
    end

    def resolved_instance_port_signal_spec(port_handler)
      port = port_handler.port
      params = port_handler.instance_handle.params
      SignalSpec.new(
        "#{port_handler.instance_handle.inst_name}_#{port_handler.name}",
        width: resolve_instance_port_expr(port.width, params),
        signed: port.signed,
        packed_dims: port.packed_dims.map { |dim| resolve_instance_port_expr(dim, params) },
        unpacked_dims: port.unpacked_dims.map { |dim| resolve_instance_port_expr(dim, params) }
      )
    end

    def resolve_instance_port_expr(expr, params)
      case expr
      when Integer
        expr
      when LiteralExpr
        expr
      when String
        params.fetch(expr, expr)
      when RawExpr
        resolve_instance_port_raw_expr(expr.source, params)
      else
        expr
      end
    end

    def resolve_instance_port_raw_expr(source, params)
      resolved = source.dup
      params.each do |name, value|
        resolved = resolved.gsub(/\b#{Regexp.escape(name.to_s)}\b/, value.to_s)
      end

      resolved
    end

    def connect_instance_port(port, signal)
      port.instance_handle.connect(port.name, signal)
      port.instance_handle
    end

    def write_sv_output(sv, output)
      return if output.nil?

      if output == "-"
        $stdout.puts(sv)
        return
      end

      FileUtils.mkdir_p(File.dirname(output))
      File.write(output, "#{sv}\n")
    end
  end
end
