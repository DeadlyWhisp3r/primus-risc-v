`timescale 1ns / 1ps
import primus_core_pkg::*;
module wb_stage (
  input logic [31:0] wb_rdata_i,
  input logic [31:0] wb_npc_i,
  input logic [31:0] wb_alu_res_i,
  input logic [4:0]  wb_rd_addr_i,
  input logic        wb_we_i,
  input wb_sel_e     wb_sel_i,

  // Data written to the register file
  output logic [31:0] wb_data_o,
  output logic [4:0]  wb_rd_addr_o,
  output logic        wb_we_o
);

  assign wb_rd_addr_o = wb_rd_addr_i;
  assign wb_we_o      = wb_we_i;

  always_comb begin
    case (wb_sel_i)
        WB_MEM: wb_data_o  = wb_rdata_i;
        WB_ALU: wb_data_o  = wb_alu_res_i;
        WB_PC4: wb_data_o  = wb_npc_i;
        default: wb_data_o = wb_alu_res_i;
    endcase
  end
endmodule
