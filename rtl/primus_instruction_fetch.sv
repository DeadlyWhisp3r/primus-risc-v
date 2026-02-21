`timescale 1ns / 1ps

module primus_instruction_fetch(
  input           clk_i,
  input           rst_ni,              // Active low reset
  input  [31:0]   pc_i,                // Program counter

  // writer interface
  output logic [31:0]      ir_o,          // Instruction register
  output logic [31:0]      npc_o          // Next program counter

);

  logic [31:0] pc_d, pc_q, ir_d, ir_q, npc_d, npc_q;

  // Instantiate module instruction memory
  inst_mem a_inst_mem (
  .clka(clk_i),    // input wire clka
  .wea('0),      // input wire [0 : 0] wea
  .addra(pc_q),  // input wire [9 : 0] addra
  .dina('0),    // input wire [31 : 0] dina
  .douta(ir_q)  // output wire [31 : 0] douta
);

  // input assignments
  assign pc_q    = pc_i;

  // output assignments
  assign ir_o    = ir_d;
  assign npc_o   = npc_d;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      pc_d  <= '0;
      ir_d  <= 32'h00000013; // Resets to NOP
      npc_d <= '0;
    end else begin
      pc_d  <= pc_q;
      ir_d  <= ir_q;
      npc_d <= npc_q;
    end
  end

  always_comb begin
    npc_q = pc_d + 4; // Progress to next PC
  end

endmodule 
