module ImportedCounter #(
  parameter int WIDTH = 12,
  parameter int DEPTH = WIDTH * 2
) (
  input  logic             clk,
  input  logic             rst_n,
  input  logic [WIDTH-1:0] din,
  output logic [WIDTH-1:0] dout,
  output logic [7:0]       mem [3:0]
);
  always_comb begin
    dout = rst_n ? din : '0;
    mem[0] = clk ? 8'h11 : 8'h22;
    mem[1] = din[7:0];
    mem[2] = din[7:0] ^ 8'h55;
    mem[3] = din[7:0] + 8'd1;
  end
endmodule
