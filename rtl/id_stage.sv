`timescale 1ns / 1ps

module id_stage(
  input clk_i,
  input rst_ni,
  input [31:0] npc_i,
  input [31:0] inst_i,
  // Write-back input, value to be stored from wb-stage
  input [31:0] wb_w_addr_i,
  input [31:0] wb_w_data_i,
  
  // Output of source registers rs1 & rs2
  output [31:0] id_rs1_o,
  output [31:0] id_rs2_o,
  // Next program counter
  output [31:0] npc_o,
  // Immediate value
  output [31:0] imm_o
);

  // Source registers rs1 & rs2
  logic [31:0] id_rs1_q, id_rs1_d;
  logic [31:0] id_rs2_q, id_rs2_d;

  // Control signals to be sent to the execute stage
  // --- ex_stage signals ---
  output logic       alu_src,     // ALU operand: 0 = rs2, 1 = Immediate
  alu_op_e           alu_op,      // ALU operation: ALU_ADD = add, ALU_SUB = sub, ALU_FROM_FUNCT= use funct3/7, ALU_PASS_B == pass-through rs2
  // --- mem_stage signals ---
  output logic       mem_read,    // Enable read from Data Memory (Load)
  output logic       mem_write,   // Enable write to Data Memory (Store)
  // --- wb_stage signals ---
  output logic       reg_write,   // Enable signal for writing back into id_regfile
  wb_sel_e           wb_sel,      // Data used for rd: WB_ALU = ALU result, WB_MEM = Memory data, WB_PC4 = PC + 4
  // --- flow control signals ---
  output logic       is_branch,   // High for branches
  output logic       is_jump      // High for jumps

  // Instantiate module instruction memory
  id_regfile a_id_regfile (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .we_i(wb_we_i),
    .w_addr(wb_w_addr),
    .w_data(wb_w_data),
    .rs1_addr(inst_i[24:20]),
    .rs2_addr(inst_i[19:15]),
    .rs1_o(id_rs1_d),
    .rs2_o(id_rs2_d)
  );

  output logic [DATA_WIDTH-1] rs1_o,
  output logic [DATA_WIDTH-1] rs2_o
  
always_comb begin
    // Default assignments (prevents unwanted latches)
    alu_src    = 0;
    mem_to_reg = 0;
    reg_write  = 0;
    mem_read   = 0;
    mem_write  = 0;
    is_branch  = 0;
    is_jump    = 0;
    alu_op     = 2'b00;

    // Logic for the Control Signals
    // Cast the opcode bits in the instruction to the opcode enum
    case (opcode_e'(instr[6:0])) // Static cast for readability
      OP: begin
          reg_write = 1;
          alu_op    = ALU_FROM_FUNCT;
      end

      OP_IMM: begin
          reg_write = 1;
          alu_src   = 1; // Use Immediate
          alu_op    = ALU_FROM_FUNCT;
      end

      LOAD: begin
          reg_write = 1;
          alu_src   = 1;
          mem_read  = 1;
          wb_sel    = WB_MEM; // Data comes from RAM
      end

      STORE: begin
          alu_src   = 1;
          mem_write = 1;
      end

      BRANCH: begin
          is_branch = 1;
          alu_op    = ALU_SUB; // ALU subtraction for branch comparison
      end

      JAL: begin
          reg_write = 1;
          is_jump   = 1;
          wb_sel    = WB_PC4; // Save return address
      end

      JALR: begin
          reg_write = 1;
          alu_src   = 1;
          is_jump   = 1;
          wb_sel    = WB_PC4;
      end

      LUI: begin
          reg_write = 1;
          alu_src   = 1;
          alu_op    = ALU_PASS_B; // Pass the Upper Imm to rd
      end

      AUIPC: begin
          reg_write = 1;
          alu_src   = 1;
          // Note: AUIPC needs PC as ALU input A, handled in EX stage mux
      end
    endcase
  end
