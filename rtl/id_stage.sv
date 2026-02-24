`timescale 1ns / 1ps
import primus_core_pkg::*;

module id_stage(
  input clk_i,
  input rst_ni,
  input [31:0] npc_i,
  input [31:0] instr_i,
  // Write-back input, value to be stored from wb-stage
  input [31:0] wb_w_addr_i,
  input [31:0] wb_w_data_i,
  input        wb_we_i,
  
  // Output of source registers rs1 & rs2
  output [31:0] id_rs1_o,
  output [31:0] id_rs2_o,
  // Next program counter
  output [31:0] npc_o,
  // Immediate value
  output logic [31:0] imm_o,
  // Control signals for ex-stage
  output ctrl_t id_ctrl_o
);

  // Source registers rs1 & rs2
  logic [31:0] id_rs1_q, id_rs1_d;
  logic [31:0] id_rs2_q, id_rs2_d;
  logic [31:0] npc_q, npc_d;
  logic [31:0] imm_q, imm_d;
  // Struct for control signals
  ctrl_t ctrl_d, ctrl_q;

  assign id_rs1_o  = id_rs1_q;
  assign id_rs2_o  = id_rs2_q;
  assign npc_o     = npc_q;
  assign imm_o     = imm_q;
  assign id_ctrl_o = ctrl_q;

  // Instantiate module instruction memory
  id_regfile a_id_regfile (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .we_i(wb_we_i),
    .w_addr_i(wb_w_addr_i),
    .w_data_i(wb_w_data_i),
    .rs1_addr_i(instr_i[24:20]),
    .rs2_addr_i(instr_i[19:15]),
    .rs1_o(id_rs1_d),
    .rs2_o(id_rs2_d)
  );

always_comb begin
    // Default assignments (prevents unwanted latches)
    ctrl_d.alu_src    = 0;
    ctrl_d.alu_op     = ALU_ADD;
    ctrl_d.mem_read   = 0;
    ctrl_d.mem_write  = 0;
    ctrl_d.reg_write  = 0;
    ctrl_d.wb_sel     = WB_ALU;
    ctrl_d.is_branch  = 0;
    ctrl_d.is_jump    = 0;

    // Logic for the Control Signals
    // Cast the opcode bits in the instruction to the opcode enum
    case (opcode_e'(instr_i[6:0])) // Static cast for readability
      OP: begin
          ctrl_d.reg_write = 1;
          ctrl_d.alu_op    = ALU_FROM_FUNCT;
      end

      OP_IMM: begin
          ctrl_d.reg_write = 1;
          ctrl_d.alu_src   = 1; // Use Immediate
          ctrl_d.alu_op    = ALU_FROM_FUNCT;
      end

      LOAD: begin
          ctrl_d.reg_write = 1;
          ctrl_d.alu_src   = 1;
          ctrl_d.mem_read  = 1;
          ctrl_d.wb_sel    = WB_MEM; // Data comes from RAM
      end

      STORE: begin
          ctrl_d.alu_src   = 1;
          ctrl_d.mem_write = 1;
      end

      BRANCH: begin
          ctrl_d.is_branch = 1;
          ctrl_d.alu_op    = ALU_SUB; // ALU subtraction for branch comparison
      end

      JAL: begin
          ctrl_d.reg_write = 1;
          ctrl_d.is_jump   = 1;
          ctrl_d.wb_sel    = WB_PC4; // Save return address
      end

      JAL_R: begin
          ctrl_d.reg_write = 1;
          ctrl_d.alu_src   = 1;
          ctrl_d.is_jump   = 1;
          ctrl_d.wb_sel    = WB_PC4;
      end

      LUI: begin
          ctrl_d.reg_write = 1;
          ctrl_d.alu_src   = 1;
          ctrl_d.alu_op    = ALU_PASS_B; // Pass the Upper Imm to rd
      end

      AUIPC: begin
          ctrl_d.reg_write = 1;
          ctrl_d.alu_src   = 1;
          // Note: AUIPC needs PC as ALU input A, handled in EX stage mux
      end
    endcase

    // Extraction of fields in the instruction types
    case (instr_type_e'(instr_i[6:0]))
      R_TYPE: begin
        imm_d = 'b0;
      end

      I_TYPE: begin
        // Sign-extended immediate
        // For negative numbers, MSBs padded with ones other wise zeroes
        imm_d = {{20{instr_i[31]}}, instr_i[31:20]};
      end

      S_TYPE: begin
        imm_d = {{20{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};
      end

      B_TYPE: begin
        // For Branch and Jump instructions the immediate is split up more in the instruction and a zero in the end because
        // instructions are always factor of two (32 bit instructions)
        imm_d = {{20{instr_i[31]}}, instr_i[31], instr_i[7], instr_i[30:25], instr_i[11:8], 1'b0};
      end

      U_TYPE: begin
        imm_d = {{20{instr_i[31]}}, instr_i[31:12]};
      end

      J_TYPE: begin
        imm_d = {{11{instr_i[31]}}, instr_i[31], instr_i[19:12], instr_i[20], instr_i[30:21], 1'b0};
      end
    endcase
  end

  always_comb begin
    npc_d = npc_i;
  end

  always_ff @(negedge(rst_ni) or posedge(clk_i)) begin
    if(!rst_ni) begin
      id_rs1_q <= 'b0;
      id_rs2_q <= 'b0;
      npc_q    <= 'b0;
      imm_q    <= 'b0;
      ctrl_q   <= 'b0;
    end else begin
      id_rs1_q <= id_rs1_d;
      id_rs2_q <= id_rs2_d;
      npc_q    <= npc_d;
      imm_q    <= imm_d; 
      ctrl_q   <= ctrl_d;
    end
  end

endmodule
