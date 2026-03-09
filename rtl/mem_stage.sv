`timescale 1ns / 1ps
import primus_core_pkg::*;

module mem_stage(
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
  // Write enable to the MEM data, used for stores
  input logic         mem_ram_we_i,
  // Write enable for the WB stage to write to the register file, low for
  // stores, branches, etc.
  input logic         mem_we_i,

  // Signals for the Memory place in the top module
  // Data read from the RAM
  input  logic [31:0] mem_ram_rdata_i,
  output logic [31:0] mem_ram_addr_o,
  output logic [31:0] mem_ram_wdata_o,
  output logic        mem_ram_we_o,


  // Signals for the WB stage
  // The data read from the memory
  output logic [31:0] mem_wb_rdata_o,
  // WB can choose to write either the mem_rdata or alu_res
  output logic [31:0] mem_wb_alu_res_o,
  output logic [4:0]  mem_wb_rd_addr_o,
  output logic        mem_wb_we_o,
  output wb_sel_e     mem_wb_sel_o

);

  logic [31:0] mem_wb_rdata_d,   mem_wb_rdata_q;
  logic [31:0] mem_wb_alu_res_d, mem_wb_alu_res_q;
  logic [4:0]  mem_wb_rd_addr_d, mem_wb_rd_addr_q;
  logic        mem_wb_we_d,  mem_wb_we_q;
  wb_sel_e     mem_wb_sel_d,  mem_wb_sel_q;

  // Assignment of next value for the clocked signals to WB stage
  assign mem_wb_rdata_d     = mem_ram_rdata_i;
  assign mem_wb_alu_res_d   = mem_alu_res_i;
  assign mem_wb_rd_addr_d   = mem_rd_addr_i;
  assign mem_wb_we_d        = mem_we_i;
  assign mem_wb_sel_d       = mem_wb_sel_i;

  // Drive external RAM
  // Signals for the DATA MEM is not clocked because it has inner clocking
  assign mem_ram_addr_o  = mem_alu_res_i;
  assign mem_ram_wdata_o = mem_rs2_data_i;
  assign mem_ram_we_o    = mem_ram_we_i;

  // Clocked signals for the WB stage
  assign mem_wb_rdata_o   = mem_wb_rdata_q;
  assign mem_wb_alu_res_o = mem_wb_alu_res_q;
  assign mem_wb_rd_addr_o = mem_wb_rd_addr_q;
  assign mem_wb_we_o   = mem_wb_we_q;
  assign mem_wb_sel_o  = mem_wb_sel_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      mem_wb_rdata_q   <= 32'b0;
      mem_wb_alu_res_q <= 32'b0;
      mem_wb_rd_addr_q <= 5'b0;
      mem_wb_we_q      <= 1'b0;
      mem_wb_sel_q     <= WB_ALU;
    end else begin
      mem_wb_rdata_q   <= mem_wb_rdata_d;
      mem_wb_alu_res_q <= mem_wb_alu_res_d;
      mem_wb_rd_addr_q <= mem_wb_rd_addr_d;
      mem_wb_we_q      <= mem_wb_we_d;
      mem_wb_sel_q     <= mem_wb_sel_d;
    end
  end

endmodule
