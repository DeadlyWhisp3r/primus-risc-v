`timescale 1ns / 1ps
import primus_core_pkg::*;

module primus_risc_v_top(
  // Input for top module
  input logic clk_i,
  input rst_ni
);


  logic [31:0]  pc;
  logic [31:0]  if_ir;
  logic [31:0]  if_npc;
  logic [31:0]  id_rs1;
  logic [31:0]  id_rs2;
  logic [31:0]  id_npc;
  logic [31:0]  id_imm;

  if_stage a_if_stage (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .pc_i(pc),
    .ir_o(if_ir),
    .npc_o(if_npc)
  );

  id_stage a_id_stage (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .npc_i(if_npc),
    .instr_i(if_ir),
    .wb_w_addr_i('b0),
    .wb_w_data_i('b0),
    .id_rs1_o(id_rs1),
    .id_rs2_o(id_rs2),
    .npc_o(id_npc),
    .imm_o(id_imm),
    .id_ctrl_o(id_ctrl)
  );

endmodule
