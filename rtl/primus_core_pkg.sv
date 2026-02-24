package primus_core_pkg;
  typedef enum logic[6:0] {
    OP = 'b0110011,
    OP_IMM = 'b0010011,
    LOAD = 'b0000011,
    STORE = 'b0100011,
    BRANCH = 'b1100011,
    JAL = 'b1101111,
    JAL_R = 'b1100111,
    LUI = 'b0110111,
    AUIPC = 'b0010111,
    SYSTEM = 'b1110011
  } opcode_e;

  // ALU Operations
  typedef enum logic [1:0] {
    ALU_ADD        = 2'b00, // Addition
    ALU_SUB        = 2'b01, // Subtraction
    ALU_FROM_FUNCT = 2'b10, // Get values funct3/funct7
    ALU_PASS_B     = 2'b11  // Pass input B straight to ALU output
  } alu_op_e;

  // Write-back Source
  typedef enum logic [1:0] {
    WB_ALU  = 2'b00, // Write ALU result to rd
    WB_MEM  = 2'b01, // Write Memory data to rd
    WB_PC4  = 2'b10  // Write PC+4 to rd (for Jumps)
  } wb_sel_e;

  // Control signals to be sent to the execute stage
  typedef struct packed {
    // --- ex_stage signals ---
    logic     alu_src;     // ALU operand: 0 = rs2, 1 = Immediate
    alu_op_e  alu_op;      // ALU operation: ALU_ADD = add, ALU_SUB = sub, ALU_FROM_FUNCT= use funct3/7, ALU_PASS_B == pass-through rs2 or imm
    // --- mem_stage signals ---
    logic     mem_read;    // Enable read from Data Memory (Load)
    logic     mem_write;   // Enable write to Data Memory (Store)
    // --- wb_stage signals ---
    logic     reg_write;   // Enable signal for writing back into id_regfile
    wb_sel_e  wb_sel;      // Data used for rd: WB_ALU = ALU result, WB_MEM = Memory data, WB_PC4 = PC + 4
    // --- flow control signals ---
    logic     is_branch;   // High for branches
    logic     is_jump;      // High for jumps
  } ctrl_t;

  typedef enum logic [2:0] {
    R_TYPE = 3'b000, // Register-Register: add, sub, and, or
    I_TYPE = 3'b001, // Register-Immediate: addi, lw, jalr
    S_TYPE = 3'b010, // Store: sw, sb, sh
    B_TYPE = 3'b011, // Branch: beq, bne, blt
    U_TYPE = 3'b100, // Upper Immediate: lui, auipc
    J_TYPE = 3'b101  // Jump: jal
  } instr_type_e;
endpackage
