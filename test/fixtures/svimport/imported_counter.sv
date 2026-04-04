`include "defs.svh"

module ImportedCounter #(
  parameter int WIDTH = `IMPORTED_WIDTH,
  parameter int DEPTH = WIDTH * 2
) (
  input  logic             clk,
  input  logic             rst_n,
  input  logic [WIDTH-1:0] din,
  output logic [WIDTH-1:0] dout,
  output logic [7:0]       mem [4]
);
endmodule
