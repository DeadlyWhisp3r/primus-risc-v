`timescale 1ns / 1ps

module instruction_memory(
  input  clk_i,
  input  rst_ni,
  input [31:0] addr_i,

  output logic [31:0] inst_o

);

  logic [31:0] inst_mem_q [1024];
  logic [31:0] inst_mem_d [1024];

  always_comb begin
    // First two bits used for byte addressing
    // 10 bits = 2^10 = 1024
    inst_o = inst_mem_d[addr_i[11:2]];
  end

  // We want to instanciate the BRAM therefore no rst used
  always_ff @(posedge clk_i) begin
    inst_mem_d <= inst_mem_q;
  end

  initial begin
    // Initialize with zeros or load a hex file
    //for (int i = 0; i < 1024; i++) mem[i] = 32'h00000014;
    
    // Example: Add a NOP or an instruction at address 0
    // mem[0] = 32'h00000013; 
    
    // Better yet, load a file:
    $readmemh("program.mem", inst_mem_d);
  end
endmodule
