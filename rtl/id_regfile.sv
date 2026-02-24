`timescale 1ns / 1ps

module id_regfile #(
  parameter DATA_WIDTH = 64
)(
  input logic clk_i,
  input logic rst_ni,
  // Write enable
  input logic we_i,
  // Write address
  input logic [31:0] w_addr_i,
  // Write data
  input logic [DATA_WIDTH-1:0] w_data_i,
  // Address size of 6 bits = 64 registers
  input logic [4:0] rs1_addr_i,
  input logic [4:0] rs2_addr_i,

  output logic [DATA_WIDTH-1:0] rs1_o,
  output logic [DATA_WIDTH-1:0] rs2_o
);

  // Implement 31 integer registers skipping x0 since
  // it is hardwired to 0
  logic [DATA_WIDTH-1:0] x_reg_q [31:1];
  logic [DATA_WIDTH-1:0] x_reg_d [31:1];

  // Write logic
  always_comb begin
    // Default values
    x_reg_d = x_reg_q;

    if(we_i && (w_addr_i != 0)) begin
      // Write to the integer register
      x_reg_d[w_addr_i] = w_data_i;
    end
  end

  // Register functionality
  always_ff@(posedge(clk_i) or negedge(rst_ni)) begin
    if(!rst_ni) begin
      for (int i = 1; i < 32; i++) begin
        x_reg_q[i] <= '0; 
      end
    end else begin
      for (int i = 1; i < 32; i++) begin
        x_reg_q[i] <= x_reg_d[i]; 
      end
    end
  end
  
  // Read logic: If addr = 0 then x0 which is always 0 otherwise take the
  // specific register
  assign rs1_o = (rs1_addr_i == 5'b0) ? '0 : x_reg_q[rs1_addr_i];
  assign rs2_o = (rs2_addr_i == 5'b0) ? '0 : x_reg_q[rs2_addr_i];
endmodule
