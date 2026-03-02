`timescale 1ns / 1ps
import primus_core_pkg::*;

module ex_stage(
  input               clk_i,
  input               rst_ni,
  // MUX sel to write ALU result, MEM data or PC+4
  input wb_sel_e      mem_wb_sel_i,
  // The address for the load/store
  input logic [31:0]  mem_alu_res_i,
  // The data to be written to the memory
  input logic [31:0]  mem_rs2_data_i,
  // The register where to store the loaded data
  input [4:0]         mem_rd_addr_i,
  input logic         mem_write_i,

  // Signals for the Memory place in the top module
  output logic [31:0] mem_ram_addr_o,
  output logic [31:0] mem_ram_wdata_o,
  output logic        mem_ram_we_o,
  // Data read from the RAM
  input logic [31:0] mem_ram_rdata_i,

  // Signals for the WB stage
  // The data read from the memory
  output logic [31:0] mem_rdata_o,
  // WB can choose to write either the mem_rdata or alu_res
  output logic [31:0] mem_alu_res_o,
  output logic [4:0]  mem_rd_addr_o,
  output logic        mem_reg_write_o,
  input wb_sel_e      mem_wb_sel_o

);

  // Drive external RAM
  assign mem_ram_addr_o = mem_alu_res_i;
  assign mem_ram_wdata_o = mem_rs2_data_i;
  assign mem_ram_we_o    = mem_write_i;

  assign mem_rdata_o     = mem_ram_rdata_i;
  assign mem_alu_res_o   = mem_alu_res_i;
  assign mem_rd_addr_o   = mem_rd_addr_i;
  assign mem_wb_sel_i    = mem_wb_sel_o;

endmodule
