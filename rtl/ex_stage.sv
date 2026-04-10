`timescale 1ns / 1ps
import primus_core_pkg::*;

module ex_stage(
  input logic         clk_i,
  input logic         rst_ni,
  input logic [31:0]  ex_pc_i,
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
  input logic [31:0]  ex_ex_fwd_rs1_i,
  input logic [31:0]  ex_mem_fwd_rs1_i,
  input logic [4:0]   ex_rs1_reg_addr_i,
  input logic [31:0]  ex_ex_fwd_rs2_i,
  input logic [31:0]  ex_mem_fwd_rs2_i,
  input logic [4:0]   ex_rs2_reg_addr_i,
  input logic         id_predict_taken_i,

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
  // Combinational branch target — same cycle as flush, for same-cycle PC redirect
  output logic [31:0] ex_npc_comb_o,
  output wb_sel_e     ex_wb_sel_o,
  // Actual branch outcome fed back to the branch predictor in ID
  output logic        ex_br_taken_o,
  // Enable for the predictor FSM — high only when a branch is in EX
  output logic        ex_is_branch_o,
  // Memory access op forwarded to MEM for load/store width and sign extension
  output mem_op_e     ex_mem_op_o

);

  // Pipeline register signals
  logic [31:0] npc_d,            npc_q;
  logic        pc_sel_d,         pc_sel_q;
  logic [31:0] alu_res_d,        alu_res_q;
  logic [4:0]  rd_addr_d,        rd_addr_q;
  logic [4:0]  rd_addr_q2,       rd_addr_q3;
  logic        mem_we_d,         mem_we_q;
  logic        reg_write_d,      reg_write_q;
  wb_sel_e     wb_sel_d,         wb_sel_q;
  // rs2 must be registered: when a STORE is in MEM, fwd_rs2 already reflects the
  // next instruction in EX, not the store's data.  Capture it here so mem_rs2_data_i
  // always carries the value computed while that instruction was in EX.
  logic [31:0] rs2_q;
  mem_op_e     mem_op_d,        mem_op_q;
  logic        ex_ex_rs1_addr_match;
  logic        ex_mem_rs1_addr_match;
  logic        ex_ex_addr_match;
  logic        ex_mem_addr_match;

  // Internal signals
  logic [31:0] alu_in_a;
  logic [31:0] alu_in_b;
  logic [31:0] fwd_rs1;
  logic [31:0] fwd_rs2;
  logic        br_taken;

  // rd_addr != 0 guard: x0 is hardwired to zero and never a valid forwarding source.
  // Without this, a NOP bubble (rd_addr_q = 0 from the load-use stall injecting id_rd_addr_q <= 0)
  // spuriously matches any instruction that reads x0 (e.g. beqz = beq rs1, x0, offset),
  // forwarding stale alu_res_q instead of the correct zero.
  assign ex_ex_rs1_addr_match  = (ex_rs1_reg_addr_i == rd_addr_q)  && (rd_addr_q  != 5'b0);
  assign ex_mem_rs1_addr_match = (ex_rs1_reg_addr_i == rd_addr_q2) && (rd_addr_q2 != 5'b0);
  assign ex_ex_addr_match      = (ex_rs2_reg_addr_i == rd_addr_q)  && (rd_addr_q  != 5'b0);
  assign ex_mem_addr_match     = (ex_rs2_reg_addr_i == rd_addr_q2) && (rd_addr_q2 != 5'b0);

  // Forwarded rs1 — used by branch comparator regardless of alu_a_sel
  always_comb begin
    fwd_rs1 = ex_rs1_i;
    if (ex_ex_rs1_addr_match) begin
      fwd_rs1 = ex_ex_fwd_rs1_i;
    end else if (ex_mem_rs1_addr_match) begin
      fwd_rs1 = ex_mem_fwd_rs1_i;
    end
  end

  // Forwarded rs2 — used by branch comparator and STORE data path
  always_comb begin
    fwd_rs2 = ex_rs2_i;
    if (ex_ex_addr_match) begin
      fwd_rs2 = ex_ex_fwd_rs2_i;
    end else if (ex_mem_addr_match) begin
      fwd_rs2 = ex_mem_fwd_rs2_i;
    end
  end

  always_comb begin
    if (ex_ctrl_i.alu_a_sel == ALU_A_PC) begin
      alu_in_a = ex_pc_i;
    end else begin
      alu_in_a = fwd_rs1;
    end
  end

  always_comb begin
    if (ex_ctrl_i.alu_b_sel == ALU_B_IMM) begin
      alu_in_b = ex_imm_i;
    end else begin
      alu_in_b = fwd_rs2;
    end
  end

  // Signal if there is a instruction jump or just increment by 4
  assign pc_sel_d = (ex_ctrl_i.is_branch && br_taken  && !id_predict_taken_i) ||
                  (ex_ctrl_i.is_branch && !br_taken &&  id_predict_taken_i) ||
                  (ex_ctrl_i.is_jump   && !id_predict_taken_i);

  // Internal clocked signals next state
  // For branches/jumps use the ALU result (handles JALR rs1+imm correctly).
  // For not-taken mispredictions ex_npc_i carries the sequential PC from ID.
  assign npc_d = (br_taken || ex_ctrl_i.is_jump) ? alu_res_d : ex_npc_i;
  assign rd_addr_d           = ex_rd_addr_i;
  assign mem_we_d            = ex_ctrl_i.mem_write;
  assign reg_write_d         = ex_ctrl_i.reg_write;
  assign wb_sel_d            = ex_ctrl_i.wb_sel;
  assign mem_op_d            = ex_ctrl_i.mem_op;

  // Outputs assigned by current state
  assign ex_pc_sel_o         = pc_sel_q;
  assign ex_npc_o            = npc_q;
  assign ex_rd_addr_o        = rd_addr_q;
  assign ex_mem_we_o         = mem_we_q;
  assign ex_reg_write_o      = reg_write_q;
  assign ex_wb_sel_o         = wb_sel_q;
  assign ex_pipeline_flush_o = pc_sel_d;
  assign ex_npc_comb_o       = npc_d;
  // ALU result forwarded to MEM stage (data memory address / WB data)
  assign ex_alu_res_o        = alu_res_q;
  // Branch/jump target address
  assign ex_target_pc_o      = alu_res_q;

  // Value to be written to the Data mem (forwarded rs2, not alu_in_b which may be imm)
  assign ex_rs2_o            = rs2_q;
  assign ex_br_taken_o       = br_taken && ex_ctrl_i.is_branch;
  assign ex_is_branch_o      = ex_ctrl_i.is_branch;
  assign ex_mem_op_o         = mem_op_q;

  // Branch Comparator Logic (uses forwarded rs1/rs2)
  always_comb begin
    case (ex_ctrl_i.alu_br_op)
      BR_EQ:  br_taken = (fwd_rs1 == fwd_rs2);
      BR_NE:  br_taken = (fwd_rs1 != fwd_rs2);
      BR_LT:  br_taken = ($signed(fwd_rs1) <  $signed(fwd_rs2));
      BR_GE:  br_taken = ($signed(fwd_rs1) >= $signed(fwd_rs2));
      BR_LTU: br_taken = (fwd_rs1 <  fwd_rs2);
      BR_GEU: br_taken = (fwd_rs1 >= fwd_rs2);
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
      wb_sel_q         <= WB_ALU; // Default enum value
      rs2_q            <= 32'b0;
      mem_op_q         <= MEM_W;
    end else begin
      npc_q            <= npc_d;
      pc_sel_q         <= pc_sel_d;
      alu_res_q        <= alu_res_d;
      rd_addr_q        <= rd_addr_d;
      rd_addr_q2       <= rd_addr_q;
      rd_addr_q3       <= rd_addr_q2;
      rs2_q            <= fwd_rs2;
      mem_we_q         <= mem_we_d;
      reg_write_q      <= reg_write_d;
      wb_sel_q         <= wb_sel_d;
      mem_op_q         <= mem_op_d;
    end
  end

endmodule
