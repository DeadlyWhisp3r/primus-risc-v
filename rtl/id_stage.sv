`timescale 1ns / 1ps
import primus_core_pkg::*;

module id_stage(
  input clk_i,
  input rst_ni,
  // Flush the pipeline, usually a branch taken -> grabage in the pipe
  input pipeline_flush_i,
  input [31:0] id_pc_i,
  input [31:0] id_npc_i,
  input [31:0] instr_i,
  // Write-back input, value to be stored from wb-stage
  input [4:0]  wb_w_addr_i,
  input [31:0] wb_w_data_i,
  input        wb_we_i,
  // Actual branch outcome from EX (only valid when ex_id_is_branch_i is high)
  input logic  ex_id_branch_taken_i,
  // High when a branch instruction is in the EX stage — enables predictor update
  input logic  ex_id_is_branch_i,
  
  // Output of source registers rs1 & rs2
  output [31:0] id_rs1_o,
  output [31:0] id_rs2_o,
  // Addresses of source operands rs1 & rs2, used for forwarding
  output [4:0]  id_rs1_addr_o,
  output [4:0]  id_rs2_addr_o,
  // The address of where the result will be written
  output [4:0]  id_rd_addr_o,
  // Current and next program counter
  output [31:0] pc_o,
  output [31:0] npc_o,
  // Immediate value
  output logic [31:0] imm_o,
  // Control signals for ex-stage
  output ctrl_t id_ctrl_o,
  // Whether the fast path redirected IF this cycle (combinational)
  output logic        id_bp_taken_o,
  // The redirect target for the fast path (combinational)
  output logic [31:0] id_bp_target_o,
  // Registered prediction — tells EX whether the fast path was already used
  output logic id_predict_taken_o
);

  // Source registers rs1 & rs2
  logic [31:0] id_rs1_q, id_rs1_d;
  logic [31:0] id_rs2_q, id_rs2_d;
  logic [4:0]  id_rs1_addr_q, id_rs1_addr_d;
  logic [4:0]  id_rs2_addr_q, id_rs2_addr_d;
  logic [4:0]  id_rd_addr_q, id_rd_addr_d;
  logic [31:0] pc_q,  pc_d;
  logic [31:0] npc_q, npc_d;
  logic [31:0] imm_q, imm_d;
  // Struct for control signals
  ctrl_t ctrl_d, ctrl_q;
  // Funct3 and funct7 fields
  logic [2:0] funct3;
  logic       f7_bit;
  // Branch prediction
  br_predict_state_e br_pred_state_q, br_pred_state_d;
  logic predict_taken_q, predict_taken_d;
  logic ctr_predicts_taken; // Raw output of the 2-bit saturating counter (WT or ST)

  assign id_rs1_o           = id_rs1_q;
  assign id_rs2_o           = id_rs2_q;
  assign id_rs1_addr_o      = id_rs1_addr_q;
  assign id_rs2_addr_o      = id_rs2_addr_q;
  assign id_rd_addr_o       = id_rd_addr_q;
  assign pc_o               = pc_q;
  assign npc_o              = npc_q;
  assign imm_o              = imm_q;
  assign id_ctrl_o          = ctrl_q;
  assign id_predict_taken_o = predict_taken_q;

  instr_type_e instr_format;

  // Instantiate module instruction memory
  id_regfile a_id_regfile (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .we_i(wb_we_i),
    .w_addr_i(wb_w_addr_i),
    .w_data_i(wb_w_data_i),
    .rs1_addr_i(instr_i[19:15]),
    .rs2_addr_i(instr_i[24:20]),
    .rs1_o(id_rs1_d),
    .rs2_o(id_rs2_d)
  );

always_comb begin
    // Default assignments (prevents unwanted latches)
    ctrl_d.alu_a_sel  = ALU_A_RS1;
    ctrl_d.alu_b_sel  = ALU_B_RS2;
    ctrl_d.alu_op     = ALU_ADD;
    ctrl_d.mem_read   = 0;
    ctrl_d.mem_write  = 0;
    ctrl_d.reg_write  = 0;
    ctrl_d.wb_sel     = WB_ALU;
    ctrl_d.is_branch  = 0;
    ctrl_d.is_jump    = 0;

    // Extract funct3 and funct7 fields for internal decoding logic
    funct3 = instr_i[14:12];
    // Bit 30 distinguishes ADD/SUB and SRL/SRA
    f7_bit = instr_i[30];
    // Register to write results to
    id_rd_addr_d  = instr_i[11:7];
    // Source register addresses, pipelined for forwarding
    id_rs1_addr_d = instr_i[19:15];
    id_rs2_addr_d = instr_i[24:20];

    // Logic for the Control Signals
    // Cast the opcode bits in the instruction to the opcode enum
    case (opcode_e'(instr_i[6:0])) // Static cast for readability
    OP: begin
          ctrl_d.reg_write = 1;
          // Look at funct3 and the bit 30 modifier
          case (funct3)
              3'b000: ctrl_d.alu_op = f7_bit ? ALU_SUB : ALU_ADD;
              3'b001: ctrl_d.alu_op = ALU_SLL;
              3'b010: ctrl_d.alu_op = ALU_SLT;
              3'b011: ctrl_d.alu_op = ALU_SLTU;
              3'b100: ctrl_d.alu_op = ALU_XOR;
              3'b101: ctrl_d.alu_op = f7_bit ? ALU_SRA : ALU_SRL;
              3'b110: ctrl_d.alu_op = ALU_OR;
              3'b111: ctrl_d.alu_op = ALU_AND;
          endcase
    end
     OP_IMM: begin
          ctrl_d.reg_write = 1;
          ctrl_d.alu_a_sel = ALU_A_RS1;
          ctrl_d.alu_b_sel = ALU_B_IMM;
          case (funct3)
              3'b000: ctrl_d.alu_op = ALU_ADD; // Note: No SUBI in RISC-V
              3'b001: ctrl_d.alu_op = ALU_SLL;
              3'b010: ctrl_d.alu_op = ALU_SLT;
              3'b011: ctrl_d.alu_op = ALU_SLTU;
              3'b100: ctrl_d.alu_op = ALU_XOR;
              3'b101: ctrl_d.alu_op = f7_bit ? ALU_SRA : ALU_SRL; // SRAI vs SRLI
              3'b110: ctrl_d.alu_op = ALU_OR;
              3'b111: ctrl_d.alu_op = ALU_AND;
          endcase
      end

      LOAD: begin
          ctrl_d.reg_write = 1;
          ctrl_d.alu_a_sel = ALU_A_RS1;
          ctrl_d.alu_b_sel = ALU_B_IMM;
          ctrl_d.alu_op    = ALU_ADD; // Address calculation (rs1 + offset)
          ctrl_d.mem_read  = 1;
          ctrl_d.wb_sel    = WB_MEM;
      end

      STORE: begin
          ctrl_d.alu_a_sel = ALU_A_RS1;
          ctrl_d.alu_b_sel = ALU_B_IMM;
          ctrl_d.alu_op    = ALU_ADD; // Address calculation (rs1 + offset)
          ctrl_d.mem_write = 1;
      end

      BRANCH: begin
          ctrl_d.is_branch = 1;
          ctrl_d.alu_a_sel = ALU_A_PC;
          ctrl_d.alu_b_sel = ALU_B_IMM; // Use Immediate for address calculation
          ctrl_d.alu_op    = ALU_ADD;   // Target = PC + Imm
          ctrl_d.alu_br_op = BR_NONE;

          // Define which comparison the separate comparator should do
          case (funct3)
              3'b000: ctrl_d.alu_br_op = BR_EQ;
              3'b001: ctrl_d.alu_br_op = BR_NE;
              3'b100: ctrl_d.alu_br_op = BR_LT;
              3'b101: ctrl_d.alu_br_op = BR_GE;
              3'b110: ctrl_d.alu_br_op = BR_LTU;
              3'b111: ctrl_d.alu_br_op = BR_GEU;
          endcase
      end

      LUI: begin
          ctrl_d.reg_write = 1;
          ctrl_d.alu_b_sel = ALU_B_IMM;
          ctrl_d.alu_op    = ALU_COPY_B;
      end

      AUIPC: begin
          ctrl_d.reg_write = 1;
          ctrl_d.alu_a_sel = ALU_A_PC; 
          ctrl_d.alu_b_sel = ALU_B_IMM; 
          ctrl_d.alu_op    = ALU_ADD; // PC + Immediate
          // Ensure your EX stage muxes PC into ALU input A for this opcode
      end
      JAL: begin
          ctrl_d.reg_write = 1;
          ctrl_d.is_jump   = 1;
          ctrl_d.alu_a_sel = ALU_A_PC;
          ctrl_d.alu_b_sel = ALU_B_IMM;
          ctrl_d.alu_op    = ALU_ADD;
          ctrl_d.wb_sel    = WB_PC4; // Save return address
      end

      JAL_R: begin
          ctrl_d.reg_write = 1;
          ctrl_d.alu_a_sel = ALU_A_RS1; // JALR target = RS1 + Imm
          ctrl_d.alu_b_sel = ALU_B_IMM;
          ctrl_d.is_jump   = 1;
          ctrl_d.wb_sel    = WB_PC4;
      end
    endcase

    case (instr_i[6:2])
      // --- I-TYPE: Mapping three different opcodes to one name ---
      5'b00100, // OP-IMM (addi, andi, etc.)
      5'b00000, // LOAD   (lw, lb, etc.)
      5'b11001: // JALR   (jump register)
          instr_format = I_TYPE;
      // --- R-TYPE ---
      5'b01100: 
          instr_format = R_TYPE;
      // --- S-TYPE ---
      5'b01000: 
          instr_format = S_TYPE;
      // --- B-TYPE ---
      5'b11000: 
          instr_format = B_TYPE;
      // --- U-TYPE: Mapping two opcodes (LUI and AUIPC) ---
      5'b01101, 
      5'b00101: 
          instr_format = U_TYPE;
      // --- J-TYPE ---
      5'b11011: 
          instr_format = J_TYPE;
      default: 
          instr_format = I_TYPE; // Safe default
    endcase

    // Extraction of fields in the instruction types
    case (instr_format)
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
        imm_d = {instr_i[31:12], 12'b0};
      end

      J_TYPE: begin
        imm_d = {{12{instr_i[31]}}, instr_i[31], instr_i[19:12], instr_i[20], instr_i[30:21], 1'b0};
      end
    endcase
  end


  // Branch prediction logic
  // Sequential logic to update state
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)
      br_pred_state_q <= SNT;
    else if (ex_id_is_branch_i)
      br_pred_state_q <= br_pred_state_d;
  end
  // Combinational logic for state transitions
  always_comb begin
    case (br_pred_state_q)
      SNT: br_pred_state_d = ex_id_branch_taken_i ? WNT : SNT;
      WNT: br_pred_state_d = ex_id_branch_taken_i ? WT  : SNT;
      WT : br_pred_state_d = ex_id_branch_taken_i ? ST  : WNT;
      ST : br_pred_state_d = ex_id_branch_taken_i ? ST  : WT;
    endcase
  end

  // Prediction output
  assign ctr_predicts_taken = (br_pred_state_q == WT || br_pred_state_q == ST);

  // predict_taken_d: high when the fast path fires for the current instruction in ID.
  // J_TYPE always redirects; B_TYPE redirects only when the counter predicts taken.
  assign predict_taken_d = (instr_format == B_TYPE && ctr_predicts_taken) ||
                            (instr_format == J_TYPE);

  // Fast path outputs used by the top-level PC mux
  assign id_bp_taken_o  = predict_taken_d;
  assign id_bp_target_o = id_pc_i + imm_d;

  always_comb begin
    pc_d  = id_pc_i;
    // NPC is always sequential; EX uses alu_res_d for the actual redirect address.
    npc_d = id_npc_i;
  end

  always_ff @(negedge(rst_ni) or posedge(clk_i)) begin
    // Active low reset and pipeline flush
    if(!rst_ni || pipeline_flush_i) begin
      id_rs1_q        <= 'b0;
      id_rs2_q        <= 'b0;
      id_rs1_addr_q   <= 'b0;
      id_rs2_addr_q   <= 'b0;
      id_rd_addr_q    <= 'b0;
      pc_q            <= 'b0;
      npc_q           <= 'b0;
      imm_q           <= 'b0;
      ctrl_q          <= 'b0;
      predict_taken_q <= 'b0;
    end else begin
      id_rs1_q        <= id_rs1_d;
      id_rs2_q        <= id_rs2_d;
      id_rs1_addr_q   <= id_rs1_addr_d;
      id_rs2_addr_q   <= id_rs2_addr_d;
      id_rd_addr_q    <= id_rd_addr_d;
      pc_q            <= pc_d;
      npc_q           <= npc_d;
      imm_q           <= imm_d;
      ctrl_q          <= ctrl_d;
      predict_taken_q <= predict_taken_d;
    end
  end

endmodule
