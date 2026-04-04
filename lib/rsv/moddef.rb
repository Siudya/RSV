# frozen_string_literal: true

module RSV
  # Top-level DSL class. Construct a SystemVerilog module description with a
  # block-based Ruby API and convert it to SV text with #to_sv.
  class ModuleDef
    attr_reader :name, :params, :ports, :locals, :stmts

    def initialize(name, &block)
      @name         = name
      @params       = []
      @ports        = []
      @locals       = []
      @stmts        = []
      @currentClock = nil
      @currentReset = nil
      return unless block_given?

      if block.arity == 1
        instance_exec(self, &block)
      else
        instance_eval(&block)
      end
    end

    # ── Parameter & port declarations ───────────────────────────────────────

    def parameter(name, value, type: "int")
      @params << ParamDecl.new(name, value, type)
    end

    def uint(name, width = 1, init: nil, signed: false, **kwargs)
      width = kwargs[:width] if kwargs.key?(:width)
      SignalSpec.new(name, width: width, signed: signed, init: init)
    end

    def input(signal, width = nil, init: nil, signed: false)
      declare_port(:input, normalize_decl_signal(signal, width, init, signed))
    end

    def output(signal, width = nil, init: nil, signed: false)
      declare_port(:output, normalize_decl_signal(signal, width, init, signed))
    end

    def inout(signal, width = nil, init: nil, signed: false)
      declare_port(:inout, normalize_decl_signal(signal, width, init, signed))
    end

    # ── Internal signal declarations ────────────────────────────────────────

    def wire(signal, width = nil, init: nil, signed: false)
      declare_local(:wire, normalize_decl_signal(signal, width, init, signed))
    end

    def logic(signal, width = nil, init: nil, signed: false)
      declare_local(:logic, normalize_decl_signal(signal, width, init, signed))
    end

    def reg(signal, width = nil, init: nil, signed: false)
      declare_local(:reg, normalize_decl_signal(signal, width, init, signed))
    end

    def expr(name, rhs, width: nil, signed: false)
      rhs_expr = RSV.normalizeExpr(rhs)
      inferred_width = width || RSV.inferExprWidth(rhs_expr)
      raise ArgumentError, "cannot infer width for expr #{name}" if inferred_width.nil?

      handler = declare_local(:wire, SignalSpec.new(name, width: inferred_width, signed: signed))
      @stmts << AssignStmt.new(handler, rhs_expr)
      handler
    end

    # ── Statements ───────────────────────────────────────────────────────────

    def assign_stmt(lhs, rhs)
      @stmts << AssignStmt.new(RSV.normalizeExpr(lhs), RSV.normalizeExpr(rhs))
    end

    def with_clk_and_rst(clock, reset)
      @currentClock = RSV.normalizeExpr(clock)
      @currentReset = RSV.normalizeExpr(reset)
      self
    end

    def always_ff(clock = nil, reset = nil, &block)
      builder = ProceduralBuilder.new.build(&block)

      if clock.is_a?(String) && reset.nil?
        @stmts << AlwaysFF.new(builder.stmts, sensitivity: clock)
        return
      end

      domain_clock, domain_reset = resolve_always_ff_domain(clock, reset)
      @stmts << AlwaysFF.new(builder.stmts, clock: domain_clock, reset: domain_reset)
    end

    def always_comb(&block)
      builder = ProceduralBuilder.new.build(&block)
      @stmts << AlwaysComb.new(builder.stmts)
    end

    def always_latch(&block)
      builder = ProceduralBuilder.new.build(&block)
      @stmts << AlwaysLatch.new(builder.stmts)
    end

    def instantiate(module_name, inst_name, params: {}, connections: {})
      normalized_connections = connections.transform_values { |signal| RSV.normalizeExpr(signal) }
      @stmts << Instance.new(module_name, inst_name, params: params, connections: normalized_connections)
    end

    # ── Output ───────────────────────────────────────────────────────────────

    def to_sv
      AssignmentValidator.new.validate(self)
      lowered = Elaborator.new.elaborate(self)
      Emitter.new.emitModule(lowered)
    end

    private

    def normalize_decl_signal(signal, width, init, signed)
      return RSV.normalizeSignalSpec(signal) unless signal.is_a?(String)

      SignalSpec.new(signal, width: width || 1, signed: signed, init: init)
    end

    def declare_port(dir, spec)
      raise ArgumentError, "#{dir} does not support init" unless spec.init.nil?

      @ports << PortDecl.new(dir, spec)
      build_handler(spec, dir)
    end

    def declare_local(kind, spec)
      @locals << build_local_decl(kind, spec)
      build_handler(spec, kind)
    end

    def build_local_decl(kind, spec)
      case kind
      when :reg
        LocalDecl.new(kind, spec, init: nil, resetInit: spec.init)
      else
        LocalDecl.new(kind, spec)
      end
    end

    def build_handler(spec, kind)
      SignalHandler.new(spec.name, width: spec.width, signed: spec.signed, kind: kind, init: spec.init)
    end

    def resolve_always_ff_domain(clock, reset)
      if clock.nil? && reset.nil?
        raise "with_clk_and_rst must be set before always_ff" unless @currentClock && @currentReset

        return [@currentClock, @currentReset]
      end

      raise ArgumentError, "always_ff expects no arguments, a sensitivity string, or explicit clock/reset" if clock.nil? || reset.nil?

      [RSV.normalizeExpr(clock), RSV.normalizeExpr(reset)]
    end
  end
end
