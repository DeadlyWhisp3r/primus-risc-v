package primus_core_pkg;
  enum bit[6:0] {
    OP = 'b0110011,
    OP_IMM = 'b0010011,
    LOAD = 'b0000011,
    STORE = 'b0100011,
    BRANCH = 'b1100011,
    JAL = 'b1101111,
    JAL_R = 'b1100111,
    LUI = 'b0110111,
    AUIPC = ='b0010111,
    SYSTEM = 'b1110011
  };

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
endpackage
