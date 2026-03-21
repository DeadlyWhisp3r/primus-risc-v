`timescale 1ns / 1ps
import primus_core_pkg::*;

module ex_stage(
  input logic         clk_i,
  input logic         rst_ni,
  input logic [31:0]  ex_npc_i,
  // Input of source registers rs1 & rs2 NOTE: possibly namned a and b instead
  input logic [31:0]  ex_rs1_i,
  input logic [31:0]  ex_rs2_i,
  // Address of the register to write results to
  input logic [4:0]   ex_rd_addr_i,
  // Immediate value
  input logic [31:0]  ex_imm_i,
  // Control signals for ex-stage
  input ctrl_t        ex_ctrl_i,
  // Signals for Forwarding to solve Data Hazards
  input logic [31:0]  ex_ex_fwd_rs2_i,
  input logic [31:0]  ex_mem_fwd_rs2_i,
  input logic [4:0]   ex_rs2_reg_addr_i,

  // Next program counter
  output logic [31:0] ex_npc_o,
  // Select signal of PC, brch/jmp or + 4, high = taken
  output logic        ex_pc_sel_o,
  // The target address for the instruction if branch is taken
  output logic [31:0] ex_target_pc_o,
  // Storing the operand rs2 in the memory
  output logic [31:0] ex_rs2_o,
  // The result of out of the ALU
  output logic [31:0] ex_alu_res_o,
  // Address of where to write the results in the WB stage
  output logic [4:0]  ex_rd_addr_o,
  // Write enable for the Data memory
  output logic        ex_mem_we_o,
  // Write enable for register file (WB stage)
  output logic        ex_reg_write_o,
  // Signal to flush the IF and ID stage if branch is taken since they have
  // wrong instruction 
  output logic        ex_pipeline_flush_o,
  output wb_sel_e     ex_wb_sel_o
  // NOTE: Pass the wb_sel so in the wb stage it knows what data to take.

);

  // Pipeline register signals
  logic [31:0] npc_d,            npc_q;
  logic        pc_sel_d,         pc_sel_q;
  logic [31:0] alu_res_d,        alu_res_q;
  logic [4:0]  rd_addr_d,        rd_addr_q;
  logic [4:0]  rd_addr_q2,       rd_addr_q3;
  logic        mem_we_d,         mem_we_q;
  logic        reg_write_d,      reg_write_q;
  logic        pipeline_flush_d, pipeline_flush_q;
  wb_sel_e     wb_sel_d,         wb_sel_q;
  logic        ex_ex_addr_match;
  logic        ex_mem_addr_match;

  // Internal signals
  logic [31:0] alu_in_a;
  logic [31:0] alu_in_b;
  logic        br_taken;

  assign ex_ex_addr_match  = (ex_rs2_reg_addr_i == rd_addr_q2);
  assign ex_mem_addr_match = (ex_rs2_reg_addr_i == rd_addr_q3);

  assign alu_in_a = (ex_ctrl_i.alu_a_sel == ALU_A_PC) ? ex_npc_i : ex_rs1_i;

  always_comb begin
    // Default assignment
    alu_in_b = ex_rs2_i;
    if (ALU_B_IMM) begin
      alu_in_b = ex_imm_i;
      // Data forwarding logic
    end else begin
      if (ex_ex_addr_match) begin
        alu_in_b = ex_ex_fwd_rs2_i;
      end
      if (ex_mem_addr_match) begin
        alu_in_b = ex_mem_fwd_rs2_i;
      end
    end
  end

  // Signal if there is a instruction jump or just increment by 4
  assign pc_sel_d = (ex_ctrl_i.is_branch && br_taken) || ex_ctrl_i.is_jump;

  // Internal clocked signals next state
  assign pipeline_flush_d    = ex_pc_sel_o; 
  assign npc_d               = ex_npc_i;
  assign rd_addr_d           = ex_rd_addr_i;
  assign mem_we_d            = ex_ctrl_i.mem_write;
  assign reg_write_d         = ex_ctrl_i.reg_write;
  assign wb_sel_d            = ex_ctrl_i.wb_sel;

  // Outputs assigned by current state
  assign ex_pc_sel_o         = pc_sel_q;
  assign ex_npc_o            = npc_q;
  assign ex_rd_addr_o        = rd_addr_q;
  assign ex_mem_we_o         = mem_we_q;
  assign ex_reg_write_o      = reg_write_q;
  assign ex_wb_sel_o         = wb_sel_q;
  assign ex_pipeline_flush_o = pipeline_flush_q;
  // The next address for branching or jump is calculated by the ALU
  // uses the immediate or rs2 register assign ex_alu_res_o        = alu_res_q;
  assign ex_target_pc_o      = alu_res_q;

  // Value to be written to the Data mem
  assign ex_rs2_o            = alu_in_b;

  // Branch Comparator Logic
  always_comb begin
    case (ex_ctrl_i.alu_br_op)
      BR_EQ:  br_taken = (ex_rs1_i == ex_rs2_i);
      BR_NE:  br_taken = (ex_rs1_i != ex_rs2_i);
      BR_LT:  br_taken = ($signed(ex_rs1_i) <  $signed(ex_rs2_i));
      BR_GE:  br_taken = ($signed(ex_rs1_i) >= $signed(ex_rs2_i));
      BR_LTU: br_taken = (ex_rs1_i <  ex_rs2_i);
      BR_GEU: br_taken = (ex_rs1_i >= ex_rs2_i);
      default: br_taken = 1'b0;
    endcase
  end

  ex_alu inst_ex_alu (
    .alu_op_i   (ex_ctrl_i.alu_op),
    .op_a_i  (alu_in_a),
    .op_b_i  (alu_in_b),
    .alu_res_o (alu_res_d)
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      npc_q            <= 32'b0;
      pc_sel_q         <= 1'b0;
      alu_res_q        <= 32'b0;
      rd_addr_q        <= 5'b0;
      rd_addr_q2       <= 5'b0;
      rd_addr_q3       <= 5'b0;
      mem_we_q         <= 1'b0;
      reg_write_q      <= 1'b0;
      pipeline_flush_q <= 1'b0;
      wb_sel_q         <= WB_ALU; // Default enum value
    end else begin
      npc_q            <= npc_d;
      pc_sel_q         <= pc_sel_d;
      alu_res_q        <= alu_res_d;
      rd_addr_q        <= rd_addr_d;
      rd_addr_q2       <= rd_addr_q;
      rd_addr_q3       <= rd_addr_q2;
      mem_we_q         <= mem_we_d;
      reg_write_q      <= reg_write_d;
      pipeline_flush_q <= pipeline_flush_d;
      wb_sel_q         <= wb_sel_d;
    end
  end

endmodule
