`timescale 1ns / 1ps

module id_regfile #(
  parameter DATA_WIDTH = 64
)(
  input logic clk_i,
  input logic rst_ni,
  // Write enable
  input logic we_i,
  // Write address
  input logic w_addr;
  // Write data
  input logic [DATA_WIDTH-1] w_data,
  // Address size of 6 bits = 64 registers
  input logic [5:0] rs1_addr,
  input logic [5:0] rs2_addr,

  output logic [DATA_WIDTH-1] rs1_o,
  output logic [DATA_WIDTH-1] rs2_o
);

  // Implement 31 integer registers skipping x0 since
  // it is hardwired to 0
  logic [DATA_WIDTH-1] x_reg_q [31:1];
  logic [DATA_WIDTH-1] x_reg_d [31:1];

  // 32 floating point registers
  logic [DATA_WIDTH-1] f_reg_q [31:1];
  logic [DATA_WIDTH-1] f_reg_d [31:1];

  // Write logic
  always_comb begin
    if(we_i && (w_addr != 0)) begin
      // If the MSB of the addr is high -> write to the floating point registers
      // else write to integer registers
      if(w_addr[5]) begin
        f_reg_d[w_addr] = w_data;
      end else begin
        x_reg_d[w_addr] = w_data;
      end
    end
  end

  // Register functionality
  always_ff@(posedge(clk_i) or negedge(rst_ni))
    if(!rst_ni) begin
      x_reg_q <= '0;
      f_reg_q <= '0;
    else begin
      x_reg_q <= x_reg_d;
      f_reg_q <= f_reg_d;
    end
