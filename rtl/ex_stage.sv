`timescale 1ns / 1ps
import primus_core_pkg::*;

module ex_stage(
  input               clk_i,
  input               rst_ni,
  input [31:0]        ex_npc_i,
  // Input of source registers rs1 & rs2 NOTE: possibly namned a and b instead
  input [31:0]        ex_rs1_i,
  input [31:0]        ex_rs2_i,
  // Address of the register to write results to
  input [4:0]         ex_rd_addr_i,
  // Immediate value
  input logic [31:0]  ex_imm_i,
  // Control signals for ex-stage
  input ctrl_t        ex_ctrl_i,

  // Next program counter
  output logic [31:0] ex_npc_o,
  // Select signal of PC, brch/jmp or + 4, high = taken
  output logic        ex_pc_sel_o,
  // The target address for the instruction if branch is taken
  output logic [31:0] ex_target_pc_o,
  // The result of out of the ALU
  output logic [31:0] ex_alu_res_o,
  // Signal to flush the IF and ID stage if branch is taken since they have
  // wrong instruction 
  output logic        ex_pipeline_flush_o,
  output wb_sel_e     ex_wb_sel_o;
  // NOTE: Pass the wb_sel so in the wb stage it knows what data to take.

);


logic [31:0] alu_in_a;
logic [31:0] alu_in_b;

assign alu_in_a = (ex_ctrl_i.alu_a_sel == ALU_A_PC) ? ex_npc_i : ex_rs1_i;
assign alu_in_b = (ex_ctrl_i.alu_b_sel == ALU_B_IMM) ? ex_imm_i : ex_rs2_i;

// Signal if there is a instruction jump or just increment by 4
assign ex_pc_sel_o = (ex_ctrl_i.is_branch && br_taken) || ex_ctrl_i.is_jump;
// The next address for branching or jump is calculated by the ALU
// uses the immediate or rs2 register
assign ex_target_pc_o = ex_alu_res_o;

assign ex_pipeline_flush_o = ex_pc_sel_o; 

alu u_alu (
    .operator_i   (ex_ctrl_i.alu_op),
    .operand_a_i  (alu_in_a),
    .operand_b_i  (alu_in_b),
    .ex_alu_res_o (ex_alu_res_o)
)

endmodule
