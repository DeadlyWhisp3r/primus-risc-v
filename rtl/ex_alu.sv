`timescale 1ns / 1ps
import primus_core_pkg::*;

module ex_alu(
  input  alu_op_e     alu_op,
  input  logic [31:0] op_a_i,
  input  logic [31:0] op_b_i,
  output logic [31:0] alu_res_o
);

  // ALU logic
  always_comb begin
    // Default assignments
    ex_alu_res_o = 32'b0;

    case (alu_op_e'(alu_op)
      ALU_ADD: begin
        ex_alu_res_o = op_a_i + op_b_i;
      end
      ALU_SUB: begin 
        // Implemented in logic as A + (~B + 1)
        ex_alu_res_o = op_a_i - op_b_i;
      end
      ALU_XOR: begin
        // ^ is the built in XOR operator
        ex_alu_res_o = op_a_i ^ op_b_i;
      end
      ALU_OR: begin
        ex_alu_res_o = op_a_i | op_b_i;
      end
      ALU_AND: begin
        ex_alu_res_o = op_a_i & op_b_i;
      end
      ALU_SLL: begin
        ex_alu_res_o = op_a_i << op_b_i;
      end
      ALU_SRL: begin
        ex_alu_res_o = op_a_i >> op_b_i;
      end
      ALU_SRA: begin
        ex_alu_res_o = $signed(op_a_i) >> op_b_i;
      end
      ALU_SLT: begin
        ex_alu_res_o = ($signed(op_a_i) < $signed(op_b_i)) ? 32'b1 : 32'b0;
      end
      ALU_SLTU: begin
        ex_alu_res_o = (op_a_i < op_b_i) ? 32'b1 : 32'b0;
      end
      ALU_COPY_B: begin
        ex_alu_res_o = op_b_i;
      end
    endcase
  end

endmodule
