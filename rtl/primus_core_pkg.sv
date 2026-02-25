jackage primus_core_pkg;
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
  typedef enum logic [3:0] {
    // Basic Arithmetic
    ALU_ADD  = 4'b0000, // Addition: Result = A + B
    ALU_SUB  = 4'b0001, // Subtraction: Result = A - B

    // Logical Operations
    ALU_XOR  = 4'b0010, // Bitwise XOR: Result = A ^ B
    ALU_OR   = 4'b0011, // Bitwise OR: Result = A | B
    ALU_AND  = 4'b0100, // Bitwise AND: Result = A & B

    // Shifts (Logical and Arithmetic)
    ALU_SLL  = 4'b0101, // Shift Left Logical: Result = A << B[4:0]
    ALU_SRL  = 4'b0110, // Shift Right Logical: Result = A >> B[4:0] (Zero extended)
    ALU_SRA  = 4'b0111, // Shift Right Arithmetic: Result = $signed(A) >>> B[4:0] (Sign extended)
                        // Used to divide negative numbers, keeping their sign

    // Comparisons (Used for SLT/SLTI instructions)
    ALU_SLT  = 4'b1000, // Set Less Than (Signed): Result = (A < B) ? 1 : 0
    ALU_SLTU = 4'b1001, // Set Less Than (Unsigned): Result = (A <u B) ? 1 : 0

    // Special/Pass-through
    ALU_COPY_B = 4'b1010  // Pass Operand B: Result = B (Useful for LUI/AUIPC)
  } alu_op_e;

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
    // --- mem_stage signals ---
    logic        mem_read;    // Enable read from Data Memory (Load)
    logic        mem_write;   // Enable write to Data Memory (Store)
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
endpackage
