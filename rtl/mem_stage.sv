`timescale 1ns / 1ps
import primus_core_pkg::*;

module mem_stage(
  input logic         clk_i,
  input logic         rst_ni,
  input logic         pipeline_flush_i,
  input logic [31:0]  mem_npc_i,
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
  // Load/store width and sign extension decoded from funct3
  input mem_op_e      mem_mem_op_i,
  // Write enable for the WB stage to write to the register file, low for
  // stores, branches, etc.
  input logic         mem_reg_we_i,

  // Signals for the Memory place in the top module
  // Data read from the RAM
  input  logic [31:0] mem_ram_rdata_i,
  output logic [31:0] mem_ram_addr_o,
  output logic [31:0] mem_ram_wdata_o,
  output logic [3:0]  mem_ram_wbe_o,


  // Signals for the WB stage
  // The data read from the memory
  output logic [31:0] mem_wb_rdata_o,
  // WB can choose to write either the mem_rdata or alu_res
  output logic [31:0] mem_wb_alu_res_o,
  output logic [31:0] mem_npc_o,
  output logic [4:0]  mem_wb_rd_addr_o,
  output logic        mem_wb_we_o,
  output wb_sel_e     mem_wb_sel_o

);

  logic [31:0] mem_wb_rdata_d,   mem_wb_rdata_q;
  logic [31:0] mem_npc_d, mem_npc_q;
  logic [31:0] mem_wb_alu_res_d, mem_wb_alu_res_q;
  logic [4:0]  mem_wb_rd_addr_d, mem_wb_rd_addr_q;
  logic        mem_wb_we_d,  mem_wb_we_q;
  wb_sel_e     mem_wb_sel_d,  mem_wb_sel_q;

  // ── Load data extraction ───────────────────────────────────────────────────
  // Select the byte or halfword at the correct byte-lane based on addr[1:0].
  logic [7:0]  rd_byte;
  logic [15:0] rd_half;
  logic [31:0] load_data;

  always_comb begin
    // Byte lane mux
    case (mem_alu_res_i[1:0])
      2'b00: rd_byte = mem_ram_rdata_i[7:0];
      2'b01: rd_byte = mem_ram_rdata_i[15:8];
      2'b10: rd_byte = mem_ram_rdata_i[23:16];
      2'b11: rd_byte = mem_ram_rdata_i[31:24];
    endcase
    // Halfword lane mux (only addr[1] matters for 16-bit aligned accesses)
    rd_half = mem_alu_res_i[1] ? mem_ram_rdata_i[31:16] : mem_ram_rdata_i[15:0];

    case (mem_mem_op_i)
      MEM_B:  load_data = {{24{rd_byte[7]}}, rd_byte};   // LB  — sign extend
      MEM_H:  load_data = {{16{rd_half[15]}}, rd_half};  // LH  — sign extend
      MEM_W:  load_data = mem_ram_rdata_i;               // LW  — full word
      MEM_BU: load_data = {24'b0, rd_byte};              // LBU — zero extend
      MEM_HU: load_data = {16'b0, rd_half};              // LHU — zero extend
      default: load_data = mem_ram_rdata_i;
    endcase
  end

  // ── Store byte-enable and write-data generation ────────────────────────────
  // Replicate the sub-word into all lanes; the byte-enable selects the right
  // lane(s) so the BRAM only commits the correct bytes.
  logic [3:0]  wbe;
  logic [31:0] wdata;

  always_comb begin
    wdata = mem_rs2_data_i;
    wbe   = 4'b0000;
    if (mem_ram_we_i) begin
      case (mem_mem_op_i)
        MEM_B: begin  // SB — replicate byte, select one lane
          wdata = {4{mem_rs2_data_i[7:0]}};
          case (mem_alu_res_i[1:0])
            2'b00: wbe = 4'b0001;
            2'b01: wbe = 4'b0010;
            2'b10: wbe = 4'b0100;
            2'b11: wbe = 4'b1000;
          endcase
        end
        MEM_H: begin  // SH — replicate halfword, select two lanes
          wdata = {2{mem_rs2_data_i[15:0]}};
          wbe   = mem_alu_res_i[1] ? 4'b1100 : 4'b0011;
        end
        default: begin  // SW — full word
          wdata = mem_rs2_data_i;
          wbe   = 4'b1111;
        end
      endcase
    end
  end

  // Assignment of next value for the clocked signals to WB stage
  assign mem_wb_rdata_d     = load_data;
  assign mem_wb_alu_res_d   = mem_alu_res_i;
  assign mem_npc_d          = mem_npc_i;

  assign mem_wb_rd_addr_d   = mem_rd_addr_i;
  assign mem_wb_we_d        = mem_reg_we_i;
  assign mem_wb_sel_d       = mem_wb_sel_i;

  // Drive external RAM — combinatorial (BRAM has internal clocking)
  assign mem_ram_addr_o  = mem_alu_res_i;
  assign mem_ram_wdata_o = wdata;
  assign mem_ram_wbe_o   = wbe;

  // Clocked signals for the WB stage
  assign mem_wb_rdata_o   = mem_wb_rdata_q;
  assign mem_npc_o        = mem_npc_q;

  assign mem_wb_alu_res_o = mem_wb_alu_res_q;
  assign mem_wb_rd_addr_o = mem_wb_rd_addr_q;
  assign mem_wb_we_o   = mem_wb_we_q;
  assign mem_wb_sel_o  = mem_wb_sel_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      mem_wb_rdata_q   <= 32'b0;
      mem_npc_q        <= 32'b0;
      mem_wb_alu_res_q <= 32'b0;
      mem_wb_rd_addr_q <= 5'b0;
      mem_wb_we_q      <= 1'b0;
      mem_wb_sel_q     <= WB_ALU;
    end else begin
      mem_wb_rdata_q   <= mem_wb_rdata_d;
      mem_npc_q        <= mem_npc_d;
      mem_wb_alu_res_q <= mem_wb_alu_res_d;
      mem_wb_rd_addr_q <= mem_wb_rd_addr_d;
      mem_wb_we_q      <= mem_wb_we_d;
      mem_wb_sel_q     <= mem_wb_sel_d;
    end
  end

endmodule
