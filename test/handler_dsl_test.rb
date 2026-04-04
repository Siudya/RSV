# frozen_string_literal: true

require "minitest/autorun"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "rsv"

class HandlerDslTest < Minitest::Test
  def test_module_def_public_api_uses_snake_case
    mod = RSV::ModuleDef.new("SnakeApi")

    assert_respond_to mod, :assign_stmt
    assert_respond_to mod, :with_clk_and_rst
    assert_respond_to mod, :always_ff
    assert_respond_to mod, :always_comb
    assert_respond_to mod, :always_latch
    assert_respond_to mod, :to_sv

    refute_respond_to mod, :assignStmt
    refute_respond_to mod, :withClkAndRst
    refute_respond_to mod, :alwaysFf
    refute_respond_to mod, :alwaysComb
    refute_respond_to mod, :alwaysLatch
    refute_respond_to mod, :toSv
  end

  def test_handler_signals_emit_wire_and_logic_declarations
    mod = RSV::ModuleDef.new("Counter") do
      clk = input(uint("clk"))
      rstN = input(uint("rst_n"))
      count = output(uint("count", width: 16))
      seed = wire(uint("seed", width: 16, init: 0x7))
      countR = logic(uint("count_r", width: 16))

      assign_stmt(count, countR)

      always_ff("posedge #{clk} or negedge #{rstN}") do
        ifStmt("!#{rstN}") do
          nbAssign(countR, "'0")
        end
        elseStmt do
          nbAssign(countR, seed)
        end
      end
    end

    expected = <<~SV.chomp
      module Counter (
        input  logic        clk,
        input  logic        rst_n,
        output logic [15:0] count
      );

        wire  [15:0] seed    = 16'h7;
        logic [15:0] count_r;

        assign count = count_r;

        always_ff @(posedge clk or negedge rst_n) begin
          if (!rst_n) begin
            count_r <= '0;
          end else begin
            count_r <= seed;
          end
        end

      endmodule
    SV

    assert_equal expected, mod.to_sv
  end

  def test_handlers_can_be_used_in_instance_connections
    mod = RSV::ModuleDef.new("Top") do
      clk = input(uint("clk"))
      count = logic(uint("count", width: 16))

      instantiate "Counter", "u_counter",
        params: { "WIDTH" => 16 },
        connections: { "clk" => clk, "count" => count }
    end

    sv = mod.to_sv

    assert_includes sv, ".clk(clk)"
    assert_includes sv, ".count(count)"
  end

  def test_local_declarations_are_aligned
    mod = RSV::ModuleDef.new("AlignedDecls") do
      wire(uint("a"))
      logic(uint("count_r", width: 16))
      wire(uint("seed", width: 16, init: 0x7))
    end

    expected = <<~SV.chomp
      module AlignedDecls (
      );

        wire         a;
        logic [15:0] count_r;
        wire  [15:0] seed    = 16'h7;

      endmodule
    SV

    assert_equal expected, mod.to_sv
  end
end
