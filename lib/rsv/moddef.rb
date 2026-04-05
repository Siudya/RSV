# frozen_string_literal: true

require "fileutils"

module RSV
  # Base class for class-based module definitions.
  #
  # Example:
  #   class Counter < RSV::ModuleDef
  #     def build(width: 8)
  #       parameter "WIDTH", width
  #       clk = input("clk", bit)
  #       rst = input("rst", bit)
  #       out = output("count", uint("WIDTH"))
  #       countR = reg("count_r", uint("WIDTH"), init: "'0")
  #       out <= countR
  #       with_clk_and_rst(clk, rst)
  #       always_ff do
  #         svif(1) do
  #           countR <= countR + 1
  #         end
  #       end
  #     end
  #   end
  #
  #   top = Counter.new
  #   puts top.to_sv
  class ModuleDef
    UNSET_INIT = Object.new

    attr_reader :name, :params, :ports, :locals, :stmts

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
        mod
      end
    end

    def initialize(name = nil, *args, **kwargs)
      @name = name || default_module_name
      @params = []
      @ports = []
      @locals = []
      @stmts = []
      @current_clock = nil
      @current_reset = nil
      @instance_counts = Hash.new(0)

      auto_build = self.class.instance_method(:initialize).owner == ModuleDef &&
        self.class.instance_method(:build).owner != ModuleDef
      build(*args, **kwargs) if auto_build
    end

    def build(*args, **kwargs)
    end

    # ── Parameter & port declarations ───────────────────────────────────────

    def parameter(name, value, type: "int")
      @params << ParamDecl.new(name, value, type)
    end

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

    def input(name, data_type, init: UNSET_INIT)
      clock_type = data_type.instance_variable_get(:@_clock_type) || false
      reset_type = data_type.instance_variable_get(:@_reset_type) || false
      declare_port(:input, build_signal_spec(name, data_type, init: init), clock_type: clock_type, reset_type: reset_type)
    end

    def output(name, data_type, init: UNSET_INIT)
      clock_type = data_type.instance_variable_get(:@_clock_type) || false
      reset_type = data_type.instance_variable_get(:@_reset_type) || false
      declare_port(:output, build_signal_spec(name, data_type, init: init), clock_type: clock_type, reset_type: reset_type)
    end

    def inout(name, data_type, init: UNSET_INIT)
      clock_type = data_type.instance_variable_get(:@_clock_type) || false
      reset_type = data_type.instance_variable_get(:@_reset_type) || false
      declare_port(:inout, build_signal_spec(name, data_type, init: init), clock_type: clock_type, reset_type: reset_type)
    end

    # ── Internal signal declarations ────────────────────────────────────────

    def wire(name, data_type, init: UNSET_INIT)
      clock_type = data_type.instance_variable_get(:@_clock_type) || false
      reset_type = data_type.instance_variable_get(:@_reset_type) || false
      declare_local(:wire, build_signal_spec(name, data_type, init: init), clock_type: clock_type, reset_type: reset_type)
    end

    def reg(name, data_type, init: UNSET_INIT)
      clock_type = data_type.instance_variable_get(:@_clock_type) || false
      reset_type = data_type.instance_variable_get(:@_reset_type) || false
      declare_local(:reg, build_signal_spec(name, data_type, init: init), clock_type: clock_type, reset_type: reset_type)
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

    def mux1h(_sel1h, _dats, result: nil)
      raise ArgumentError, "mux1h must be used inside an always_ff, always_comb, or always_latch block"
    end

    def muxp(_sel, _dats, result: nil, lsb_first: true)
      raise ArgumentError, "muxp must be used inside an always_ff, always_comb, or always_latch block"
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
      AssignmentValidator.new.validate(self)
      lowered = Elaborator.new.elaborate(self)
      sv = Emitter.new.emit_module(lowered)
      write_sv_output(sv, output)
      sv
    end

    private

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
          unpacked_dims: data_type.unpacked_dims
        )
        data_type.append_dimensions(packed: normalized_dims + inner_packed)
      when :unpacked
        inner_unpacked = data_type.unpacked_dims.dup
        data_type = DataType.new(
          width: data_type.width,
          signed: data_type.signed,
          init: data_type.init,
          packed_dims: data_type.packed_dims,
          unpacked_dims: []
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

      if effective_init.is_a?(DataType) && !RSV.shape_matches_type?(type, effective_init)
        raise ArgumentError, "initializer shape must match declared data type for #{name}"
      end

      SignalSpec.new(
        name,
        width: type.width,
        signed: type.signed,
        init: effective_init,
        packed_dims: type.packed_dims,
        unpacked_dims: type.unpacked_dims
      )
    end

    def declare_port(dir, spec, clock_type: false, reset_type: false)
      raise ArgumentError, "#{dir} does not support init" unless spec.init.nil?

      @ports << PortDecl.new(dir, spec)
      handler = build_handler(spec, dir)
      return ClockSignal.new(handler) if clock_type
      return ResetSignal.new(handler) if reset_type

      handler
    end

    def declare_local(kind, spec, clock_type: false, reset_type: false)
      @locals << build_local_decl(kind, spec)
      handler = build_handler(spec, kind)
      return ClockSignal.new(handler) if clock_type
      return ResetSignal.new(handler) if reset_type

      handler
    end

    def build_local_decl(kind, spec)
      case kind
      when :reg
        LocalDecl.new(kind, spec, init: nil, reset_init: spec.init)
      else
        LocalDecl.new(kind, spec)
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
        unpacked_dims: spec.unpacked_dims
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
      inst_name = kwargs.delete(:inst_name) || next_instance_name(module_class)
      definition = module_class.build_definition(*args, **kwargs)
      handle = ModuleInstanceHandle.new(definition, inst_name: inst_name)
      @stmts << Instance.new(handle.module_name, handle.inst_name, params: handle.params, connections: handle.connections)
      handle
    end

    def next_instance_name(module_class)
      base_name = underscore_name(module_class.name.to_s.split("::").last)
      count = @instance_counts[base_name]
      @instance_counts[base_name] += 1
      count.zero? ? "u_#{base_name}" : "u_#{base_name}_#{count}"
    end

    def default_module_name
      self.class.name.to_s.split("::").last
    end

    def underscore_name(name)
      name.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
    end

    def instance_port(operand)
      operand if operand.is_a?(InstancePortHandler)
    end

    def append_assignment(lhs, rhs)
      lhs_port = instance_port(lhs)
      rhs_port = instance_port(rhs)

      if lhs_port || rhs_port
        raise ArgumentError, "instance port connection expects exactly one instance port" if lhs_port && rhs_port

        return connect_instance_port(lhs_port || rhs_port, lhs_port ? rhs : lhs)
      end

      stmt = AssignStmt.new(RSV.normalize_expr(lhs), RSV.normalize_expr(rhs))
      @stmts << stmt
      stmt
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
