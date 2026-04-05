# frozen_string_literal: true

require "minitest/autorun"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "rsv"

class HandlerDslTest < Minitest::Test
  def test_module_def_public_api_uses_snake_case
    mod = module_class("SnakeApi").new

    assert_respond_to mod, :with_clk_and_rst
    assert_respond_to mod, :always_ff
    assert_respond_to mod, :always_comb
    assert_respond_to mod, :always_latch
    assert_respond_to mod, :to_sv
    assert_respond_to mod, :wire
    assert_respond_to mod, :reg
    assert_respond_to mod, :bit
    assert_respond_to mod, :uint
    assert_respond_to mod, :bits
    assert_respond_to mod, :sint
    assert_respond_to mod, :clock
    assert_respond_to mod, :reset
    assert_respond_to mod, :arr
    assert_respond_to mod, :mem
    assert_respond_to mod, :mux
    assert_respond_to mod, :mux1h
    assert_respond_to mod, :muxp
    assert_respond_to mod, :cat
    assert_respond_to mod, :fill
    assert_respond_to mod, :definition
    assert_respond_to mod, :instance

    refute_respond_to mod, :instantiate
    refute_respond_to mod, :assign_stmt
    refute_respond_to mod, :logic
    refute_respond_to mod, :assignStmt
    refute_respond_to mod, :withClkAndRst
    refute_respond_to mod, :alwaysFf
    refute_respond_to mod, :alwaysComb
    refute_respond_to mod, :alwaysLatch
    refute_respond_to mod, :toSv
  end

  def test_handler_signals_emit_wire_and_logic_declarations
    mod = module_class("Counter") do
      clk = input("clk", clock)
      rst_n = input("rst_n", reset)
      count = output("count", uint(16))
      seed = wire("seed", uint(16), init: 0x7)
      count_r = reg("count_r", uint(16), init: 0)

      count <= count_r

      with_clk_and_rst(clk, rst_n.neg)
      always_ff do
        svif(1) do
          count_r <= seed
        end
      end
    end.new

    expected = <<~SV.chomp
      module Counter (
        input  logic        clk,
        input  logic        rst_n,
        output logic [15:0] count
      );

        logic [15:0] seed    = 16'h7;
        logic [15:0] count_r;

        assign count = count_r;

        always_ff @(posedge clk or negedge rst_n) begin
          if (!rst_n) begin
            count_r <= 16'h0;
          end else if (1) begin
            count_r <= seed;
          end
        end

      endmodule
    SV

    assert_equal expected, mod.to_sv
  end

  def test_string_based_always_ff_is_removed
    error = assert_raises(ArgumentError) do
      module_class("NoStringAlwaysFf") do
        clk = input("clk", bit)
        rst_n = input("rst_n", bit)
        value = reg("value", uint(8))

        always_ff("posedge #{clk} or negedge #{rst_n}") do
          value <= 0
        end
      end.new
    end

    assert_equal "always_ff expects no arguments or explicit clock/reset", error.message
  end

  def test_handlers_can_be_used_in_instance_connections
    counter_class = module_class("Counter") do
      clk = input("clk", bit)
      count = output("count", uint(16))
    end

    mod = Class.new(RSV::ModuleDef) do
      define_singleton_method(:name) { "Top" }

      define_method(:build) do
        clk = input("clk", bit)
        count = wire("count", uint(16))

        counter = counter_class.new(inst_name: "u_counter")
        counter.clk <= clk
        count <= counter.count
      end
    end.new

    sv = mod.to_sv

    assert_includes sv, "Counter u_counter ("
    assert_includes sv, ".clk(clk)"
    assert_includes sv, ".count(count)"
  end

    def test_local_declarations_are_aligned
      mod = module_class("AlignedDecls") do
      wire("a", bit)
      reg("count_r", uint(16))
      wire("seed", uint(16), init: 0x7)
      end.new

    expected = <<~SV.chomp
      module AlignedDecls (
      );

        logic        a;
        logic [15:0] count_r;
        logic [15:0] seed    = 16'h7;

      endmodule
    SV

    assert_equal expected, mod.to_sv
  end

  def test_const_emits_localparam
    mod = module_class("ConstTest") do
      a = const("MAGIC", sint(16, 0x57))
      b = const("THRESHOLD", uint(8, 42))
      out = output("out", sint(16))
      out <= a
    end.new

    sv = mod.to_sv
    assert_includes sv, "localparam signed [15:0] MAGIC"
    assert_includes sv, "16'h57"
    assert_includes sv, "localparam"
    assert_includes sv, "THRESHOLD"
    assert_includes sv, "8'h2a"
    assert_includes sv, "assign out = MAGIC;"
  end

  def test_const_requires_init_value
    error = assert_raises(ArgumentError) do
      module_class("ConstNoInit") do
        const("BAD", uint(8))
      end.new
    end

    assert_includes error.message, "const requires an init value"
  end

  def test_const_cannot_be_assigned
    error = assert_raises(ArgumentError) do
      module_class("ConstAssign") do
        a = const("RO", uint(8, 1))
        b = wire("w", uint(8))
        b <= a
        a <= b
      end.new.to_sv
    end

    assert_includes error.message, "const signal RO cannot be assigned"
  end

  private

  def module_class(name, &build_block)
    build_block ||= proc {}

    Class.new(RSV::ModuleDef) do
      define_singleton_method(:name) { name }
      define_method(:build, &build_block)
    end
  end
end
