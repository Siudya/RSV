# frozen_string_literal: true

require "minitest/autorun"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "rsv"

class SvImportTest < Minitest::Test
  FIXTURE_DIR = File.expand_path("fixtures/svimport", __dir__)
  IMPORTED_COUNTER = File.join(FIXTURE_DIR, "imported_counter.sv")

  def test_import_sv_extracts_module_signature_via_pyslang
    imported = RSV.import_sv(IMPORTED_COUNTER, top: "ImportedCounter", incdirs: [FIXTURE_DIR])
    definition = imported.build_definition

    assert_equal "ImportedCounter", imported.name
    assert_equal "ImportedCounter", definition.name
    assert_equal [
      ["WIDTH", "12", "int", "12"],
      ["DEPTH", "24", "int", "WIDTH * 2"]
    ], definition.params.map { |param| [param.name, param.value, param.param_type, param.raw_default] }
    assert_equal [
      ["clk", :input, "logic"],
      ["rst_n", :input, "logic"],
      ["din", :input, "logic [WIDTH-1:0]"],
      ["dout", :output, "logic [WIDTH-1:0]"],
      ["mem", :output, "logic [7:0] [4]"]
    ], definition.ports.map { |port| [port.name, port.dir, port.raw_type] }
  end

  def test_imported_sv_module_can_be_instantiated_inside_rsv_module
    imported = RSV.import_sv(IMPORTED_COUNTER, top: "ImportedCounter", incdirs: [FIXTURE_DIR])

    top = Class.new(RSV::ModuleDef) do
      define_singleton_method(:name) { "ImportedTop" }

      define_method(:build) do
        clk = input("clk", bit)
        rst_n = input("rst_n", bit)
        din = input("din", uint(12))
        dout = output("dout", uint(12))

        counter = imported.new(inst_name: "u_counter", WIDTH: 16)
        counter.clk <= clk
        counter.rst_n <= rst_n
        counter.din <= din
        dout <= counter.dout
      end
    end.new

    expected = <<~SV.chomp
      module ImportedTop (
        input  logic        clk,
        input  logic        rst_n,
        input  logic [11:0] din,
        output logic [11:0] dout
      );

        ImportedCounter #(
          .WIDTH(16),
          .DEPTH(32)
        ) u_counter (
          .clk(clk),
          .rst_n(rst_n),
          .din(din),
          .dout(dout)
        );

      endmodule
    SV

    assert_equal expected, top.to_sv
  end
end
