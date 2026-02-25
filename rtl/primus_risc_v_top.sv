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
  logic [4:0]   id_rd_addr;
  logic [31:0]  id_npc;
  logic [31:0]  id_imm;

  logic         ex_pipeline_flush;

  // Instruction fetch stage
  if_stage a_if_stage (
    .clk_i            (clk_i),
    .rst_ni           (rst_ni),
    .pipeline_flush_i (ex_pipeline_flush),
    .pc_i             (pc),
    .ir_o             (if_ir),
    .npc_o            (if_npc)
  );

  // Instruction decode stage
  id_stage a_id_stage (
    .clk_i            (clk_i),
    .rst_ni           (rst_ni),
    .pipeline_flush_i (ex_pipeline_flush),
    .npc_i            (if_npc),
    .instr_i          (if_ir),
    .wb_w_addr_i      ('b0),
    .wb_w_data_i      ('b0),
    .id_rs1_o         (id_rs1),
    .id_rs2_o         (id_rs2),
    .id_rd_addr_o     (id_rd_addr),
    .npc_o            (id_npc),
    .imm_o            (id_imm),
    .id_ctrl_o        (id_ctrl)
  );

  ex_stage a_ex_stage (
    .clk_i            (clk_i),
    .rst_ni           (rst_ni),
    .ex_npc_i         (id_npc),
    .ex_rs1_i         (id_rs1),
    .ex_rs2_i         (id_rs2),
    .ex_rd_addr_i     (id_rd_addr),
    .ex_imm_i         (id_imm),
    .ex_ctrl_i        (id_ctrl),
    .ex_npc_o         (ex_npc),
    .ex_pc_sel_o      (ex_pc_sel),
    .ex_target_pc_o   (ex_target_pc),
    .ex_alu_res_o     (ex_alu_res),
    .ex_pipeline_flush_o (ex_pipeline_flush),
    .ex_wb_sel_o      (wb_sel_o)

endmodule
