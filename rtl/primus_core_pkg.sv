`timescale 1ns / 1ps
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

  // Branch operations
  typedef enum logic [2:0] {
    BR_NONE,  // No branch
    BR_EQ,    // Equal (BEQ)
    BR_NE,    // Not Equal (BNE)
    BR_LT,    // Less Than (BLT)
    BR_GE,    // Greater or Equal (BGE)
    BR_LTU,   // Less Than Unsigned (BLTU)
    BR_GEU    // Greater or Equal Unsigned (BGEU)
  } br_op_e;

  // ALU Operations
  typedef enum logic [4:0] {
    // Basic Arithmetic
    ALU_ADD  = 5'b00000, // Addition: Result = A + B
    ALU_SUB  = 5'b00001, // Subtraction: Result = A - B

    // Logical Operations
    ALU_XOR  = 5'b00010, // Bitwise XOR: Result = A ^ B
    ALU_OR   = 5'b00011, // Bitwise OR: Result = A | B
    ALU_AND  = 5'b00100, // Bitwise AND: Result = A & B

    // Shifts (Logical and Arithmetic)
    ALU_SLL  = 5'b00101, // Shift Left Logical: Result = A << B[4:0]
    ALU_SRL  = 5'b00110, // Shift Right Logical: Result = A >> B[4:0] (Zero extended)
    ALU_SRA  = 5'b00111, // Shift Right Arithmetic: Result = $signed(A) >>> B[4:0] (Sign extended)
                         // Used to divide negative numbers, keeping their sign

    // Comparisons (Used for SLT/SLTI instructions)
    ALU_SLT  = 5'b01000, // Set Less Than (Signed): Result = (A < B) ? 1 : 0
    ALU_SLTU = 5'b01001, // Set Less Than (Unsigned): Result = (A <u B) ? 1 : 0

    // Special/Pass-through
    ALU_COPY_B = 5'b01010,  // Pass Operand B: Result = B (Useful for LUI/AUIPC)

    // RV32M — Multiply
    // Multiply produces a 64-bit product internally; MUL takes the lower 32 bits,
    // MULH/MULHSU/MULHU take the upper 32 bits with different sign treatments.
    // Vivado infers DSP48E1 blocks for these — single-cycle at 100 MHz is feasible.
    ALU_MUL    = 5'b01011, // MUL:    lower 32 bits of rs1 * rs2 (sign irrelevant for low word)
    ALU_MULH   = 5'b01100, // MULH:   upper 32 bits, signed   * signed
    ALU_MULHSU = 5'b01101, // MULHSU: upper 32 bits, signed   * unsigned
    ALU_MULHU  = 5'b01110, // MULHU:  upper 32 bits, unsigned * unsigned

    // RV32M — Divide / Remainder
    // NOTE: Combinational 32-bit division is slow (~30 ns on Artix-7) and may not
    // close timing at 100 MHz. A multi-cycle divider can replace these later.
    // RISC-V spec requires specific behaviour for divide-by-zero and signed overflow:
    //   DIV/REM by zero  → quotient = -1 (all ones), remainder = dividend
    //   DIVU/REMU by zero → quotient = 2^32-1 (all ones), remainder = dividend
    //   INT_MIN / -1     → quotient = INT_MIN, remainder = 0  (overflow trap suppressed)
    ALU_DIV    = 5'b01111, // DIV:  signed   quotient
    ALU_DIVU   = 5'b10000, // DIVU: unsigned quotient
    ALU_REM    = 5'b10001, // REM:  signed   remainder
    ALU_REMU   = 5'b10010  // REMU: unsigned remainder
  } alu_op_e;

  // Memory access width and sign/zero extension (used for LB/LH/LW/LBU/LHU/SB/SH/SW)
  typedef enum logic [2:0] {
    MEM_W  = 3'b000,  // Word (LW / SW)
    MEM_B  = 3'b001,  // Byte signed   (LB  / SB)
    MEM_H  = 3'b010,  // Halfword signed (LH / SH)
    MEM_BU = 3'b011,  // Byte unsigned (LBU)
    MEM_HU = 3'b100   // Halfword unsigned (LHU)
  } mem_op_e;

  // Write-back Source
  typedef enum logic [1:0] {
    WB_ALU  = 2'b00, // Write ALU result to rd
    WB_MEM  = 2'b01, // Write Memory data to rd
    WB_PC4  = 2'b10  // Write PC+4 to rd (for Jumps)
  } wb_sel_e;

  typedef enum logic {
    ALU_A_RS1 = 1'b0,
    ALU_A_PC  = 1'b1
  } alu_a_sel_e;

  typedef enum logic {
    ALU_B_RS2 = 1'b0,
    ALU_B_IMM = 1'b1
  } alu_b_sel_e;

  // Control signals to be sent to the execute stage
  typedef struct packed {
    // --- ex_stage signals ---
    alu_a_sel_e  alu_a_sel;     // ALU operand A
    alu_b_sel_e  alu_b_sel;     // ALU operand B
    alu_op_e     alu_op;      // ALU operation: defined above
    br_op_e      alu_br_op;
    // --- mem_stage signals ---
    logic        mem_read;    // Enable read from Data Memory (Load)
    logic        mem_write;   // Enable write to Data Memory (Store)
    mem_op_e     mem_op;      // Load/store width and sign extension
    // --- wb_stage signals ---
    logic        reg_write;   // Enable signal for writing back into id_regfile
    wb_sel_e     wb_sel;      // Data used for rd: WB_ALU = ALU result, WB_MEM = Memory data, WB_PC4 = PC + 4
    // --- flow control signals ---
    logic        is_branch;   // High for branches
    logic        is_jump;      // High for jumps
  } ctrl_t;

  typedef enum logic [2:0] {
    R_TYPE = 3'b000, // Register-Register: add, sub, and, or
    I_TYPE = 3'b001, // Register-Immediate: addi, lw, jalr
    S_TYPE = 3'b010, // Store: sw, sb, sh
    B_TYPE = 3'b011, // Branch: beq, bne, blt
    U_TYPE = 3'b100, // Upper Immediate: lui, auipc
    J_TYPE = 3'b101  // Jump: jal
  } instr_type_e;

  // Enum for branch prediction
  typedef enum logic [1:0] {
    SNT = 2'b00, // Strongly Not Taken
    WNT = 2'b01, // Weakly Not Taken
    WT  = 2'b10, // Weakly Taken
    ST  = 2'b11  // Strongly Taken
  } br_predict_state_e;
endpackage
