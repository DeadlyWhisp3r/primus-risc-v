`timescale 1ns / 1ps
import primus_core_pkg::*;

module ex_alu(
  input  alu_op_e     alu_op_i,
  input  logic [31:0] op_a_i,
  input  logic [31:0] op_b_i,
  output logic [31:0] alu_res_o
);

  // ALU logic
  always_comb begin
    // Default assignments
    alu_res_o = 32'b0;

    case (alu_op_e'(alu_op_i))
      ALU_ADD: begin
        alu_res_o = op_a_i + op_b_i;
      end
      ALU_SUB: begin 
        // Implemented in logic as A + (~B + 1)
        alu_res_o = op_a_i - op_b_i;
      end
      ALU_XOR: begin
        // ^ is the built in XOR operator
        alu_res_o = op_a_i ^ op_b_i;
      end
      ALU_OR: begin
        alu_res_o = op_a_i | op_b_i;
      end
      ALU_AND: begin
        alu_res_o = op_a_i & op_b_i;
      end
      ALU_SLL: begin
        // op_b_i only uses the lower 5 bits for bitshifting since 2^5 = 32
        alu_res_o = op_a_i << op_b_i[4:0];
      end
      ALU_SRL: begin
        alu_res_o = op_a_i >> op_b_i[4:0];
      end
      ALU_SRA: begin
        // Arithmetic bitshifting, extends the signed bit
        alu_res_o = $signed(op_a_i) >>> op_b_i[4:0];
      end
      ALU_SLT: begin
        alu_res_o = ($signed(op_a_i) < $signed(op_b_i)) ? 32'b1 : 32'b0;
      end
      ALU_SLTU: begin
        alu_res_o = (op_a_i < op_b_i) ? 32'b1 : 32'b0;
      end
      ALU_COPY_B: begin
        alu_res_o = op_b_i;
      end
    endcase
  end

endmodule
