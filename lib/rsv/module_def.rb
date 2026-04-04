# frozen_string_literal: true

module RSV
  # Top-level DSL class.  Construct a SystemVerilog module description with a
  # block-based Ruby API and convert it to SV text with #to_sv.
  #
  # Example:
  #   mod = RSV::ModuleDef.new("Counter") do
  #     parameter "WIDTH", 8
  #     input  "clk"
  #     output "count", width: "WIDTH"
  #     logic  "count_r", width: "WIDTH"
  #     assign_stmt "count", "count_r"
  #     always_ff "posedge clk or negedge rst_n" do
  #       if_stmt "!rst_n" do
  #         nb_assign "count_r", "'0"
  #       end
  #     end
  #   end
  #   puts mod.to_sv
  class ModuleDef
    attr_reader :name, :params, :ports, :locals, :stmts

    def initialize(name, &block)
      @name   = name
      @params = []
      @ports  = []
      @locals = []
      @stmts  = []
      instance_eval(&block) if block_given?
    end

    # ── Parameter & port declarations ─────────────────────────────────────────

    # Declare a module parameter.
    #   parameter "WIDTH", 8
    #   parameter "DEPTH", 16, type: "int"
    def parameter(name, value, type: "int")
      @params << ParamDecl.new(name, value, type)
    end

    # Declare an input port.
    #   input "clk"
    #   input "data", width: 32
    def input(name, width: 1, signed: false)
      @ports << PortDecl.new(:input, name, width, signed)
    end

    # Declare an output port.
    #   output "q", width: "WIDTH"
    def output(name, width: 1, signed: false)
      @ports << PortDecl.new(:output, name, width, signed)
    end

    # Declare an inout port.
    def inout(name, width: 1)
      @ports << PortDecl.new(:inout, name, width, false)
    end

    # ── Internal signal declarations ──────────────────────────────────────────

    # Declare a local logic signal.
    #   logic "count_r", width: "WIDTH"
    def logic(name, width: 1, signed: false)
      @locals << LogicDecl.new(name, width, signed)
    end

    # ── Statements ────────────────────────────────────────────────────────────

    # Continuous assignment:  assign <lhs> = <rhs>;
    def assign_stmt(lhs, rhs)
      @stmts << AssignStmt.new(lhs, rhs)
    end

    # always_ff @(<sensitivity>) begin ... end
    #   always_ff "posedge clk or negedge rst_n" do
    #     if_stmt "!rst_n" do
    #       nb_assign "q", "'0"
    #     end
    #   end
    def always_ff(sensitivity, &block)
      builder = ProceduralBuilder.new
      builder.instance_eval(&block) if block_given?
      @stmts << AlwaysFF.new(sensitivity, builder.stmts)
    end

    # always_comb begin ... end
    def always_comb(&block)
      builder = ProceduralBuilder.new
      builder.instance_eval(&block) if block_given?
      @stmts << AlwaysComb.new(builder.stmts)
    end

    # Module instantiation.
    #   instantiate "Counter", "u_cnt",
    #     params:      { "WIDTH" => 8 },
    #     connections: { "clk" => "clk", "count" => "cnt_out" }
    def instantiate(module_name, inst_name, params: {}, connections: {})
      @stmts << Instance.new(module_name, inst_name, params: params, connections: connections)
    end

    # ── Output ────────────────────────────────────────────────────────────────

    # Emit the module as a SystemVerilog string.
    def to_sv
      Emitter.new.emit_module(self)
    end
  end
end
