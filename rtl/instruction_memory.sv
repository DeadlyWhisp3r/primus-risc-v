module instruction_memory(
  input  clk_im,
  input  rst_ni,
  input [31:0] addr_i,

  output logic [31:0] inst_o

);

  logic [31:0] inst_mem_q [1024];
  logic [31:0] inst_mem_d [1024];

  always_comb begin
    // First two bits used for byte addressing
    // 10 bits = 2^10 = 1024
    inst_o = inst_mem_q[addr_i[10:2]];
  end

  // We want to instanciate the BRAM therefore no rst used
  always_ff @(posedge clk_i) begin
    inst_mem_d <= inst_mem_q;
  end
endmodule