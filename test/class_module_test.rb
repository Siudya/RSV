# frozen_string_literal: true

require "minitest/autorun"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "rsv"

module ClassModuleTestFixtures
  class Counter < RSV::ModuleDef
    def initialize(width: 8)
      super()

      parameter "WIDTH", width

      clk = input("clk", bit)
      rst = input("rst", bit)
      count = output("count", uint("WIDTH"))
      count_r = reg("count_r", uint("WIDTH"), init: "'0")

      count <= count_r

      with_clk_and_rst(clk, rst)
      always_ff do
        svif(1) do
          count_r <= count_r + 1
        end
      end
    end
  end

  class Top < RSV::ModuleDef
    def initialize
      super()

      clk = input("clk", bit)
      rst = input("rst", bit)
      count = output("count", uint(8))

      u_counter = Counter.new(inst_name: "u_counter", width: 8)
      u_counter.clk <= clk
      u_counter.rst <= rst
      count <= u_counter.count
    end
  end
end

class ClassModuleTest < Minitest::Test
  def test_module_def_must_be_subclassed
    assert_raises(ArgumentError) do
      RSV::ModuleDef.new("Legacy") do
      end
    end
  end

  def test_to_sv_can_write_to_stdout_with_dash
    mod = ClassModuleTestFixtures::Counter.new(width: 8)
    expected = <<~SV.chomp
      module Counter #(
        parameter int WIDTH = 8
      ) (
        input  logic             clk,
        input  logic             rst,
        output logic [WIDTH-1:0] count
      );

        logic [WIDTH-1:0] count_r;

        assign count = count_r;

        always_ff @(posedge clk or posedge rst) begin
          if (rst) begin
            count_r <= '0;
          end else if (1) begin
            count_r <= count_r + 1;
          end
        end

      endmodule
    SV

    stdout, = capture_io do
      assert_equal expected, mod.to_sv("-")
    end

    assert_equal "#{expected}\n", stdout
  end

  def test_submodule_class_instances_allow_late_port_connections
    top = ClassModuleTestFixtures::Top.new
    expected = <<~SV.chomp
      module Top (
        input  logic       clk,
        input  logic       rst,
        output logic [7:0] count
      );

        Counter #(
          .WIDTH(8)
        ) u_counter (
          .clk(clk),
          .rst(rst),
          .count(count)
        );

      endmodule
    SV

    refute_respond_to top, :instantiate
    refute_respond_to top, :assign_stmt
    refute_respond_to top, :logic
    assert_equal expected, top.to_sv
  end
end
