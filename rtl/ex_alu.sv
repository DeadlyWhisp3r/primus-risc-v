`timescale 1ns / 1ps
import primus_core_pkg::*;

module ex_alu(
  input  alu_op_e     alu_op_i,
  input  logic [31:0] op_a_i,
  input  logic [31:0] op_b_i,
  output logic [31:0] alu_res_o
);

  // 64-bit products for MULH variants — Vivado infers DSP48E1 blocks for these.
  logic [63:0] mul_ss;  // signed   * signed
  logic [63:0] mul_su;  // signed   * unsigned
  logic [63:0] mul_uu;  // unsigned * unsigned

  // mul_ss / mul_uu: the 64'() size-cast forces the operands to be evaluated in a
  // 64-bit context before multiplying, so sign/zero extension happens automatically.
  assign mul_ss = 64'($signed(op_a_i)   * $signed(op_b_i));
  assign mul_uu = 64'($unsigned(op_a_i) * $unsigned(op_b_i));

  // mul_su (MULHSU): SystemVerilog type rules say that if ANY operand in an
  // expression is unsigned the whole expression is treated as unsigned, so
  // $signed(op_a_i) * $unsigned(op_b_i) silently does unsigned * unsigned.
  // Fix: manually extend both operands to 64 bits first, then multiply as
  // signed * signed.  op_b is zero-extended (bit 63 = 0), so its signed
  // 64-bit interpretation equals its unsigned 32-bit interpretation.
  assign mul_su = $signed({{32{op_a_i[31]}}, op_a_i}) * $signed({32'b0, op_b_i});

  // RISC-V spec divide-by-zero and signed-overflow results
  // Division by zero: quotient = all-ones, remainder = dividend
  // Signed overflow (INT_MIN / -1): quotient = INT_MIN, remainder = 0
  localparam logic [31:0] INT_MIN  = 32'h8000_0000;
  localparam logic [31:0] ALL_ONES = 32'hFFFF_FFFF;

  logic div_by_zero;
  logic signed_overflow;   // INT_MIN / -1

  assign div_by_zero    = (op_b_i == 32'b0);
  assign signed_overflow = ($signed(op_a_i) == $signed(INT_MIN)) && ($signed(op_b_i) == -32'sd1);

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

      // ── RV32M — Multiply ───────────────────────────────────────────────────
      // MUL: lower 32 bits — sign of operands doesn't affect the low word
      ALU_MUL: begin
        alu_res_o = mul_uu[31:0];
      end
      // MULH/MULHSU/MULHU: upper 32 bits of 64-bit product, different sign modes
      ALU_MULH: begin
        alu_res_o = mul_ss[63:32];
      end
      ALU_MULHSU: begin
        alu_res_o = mul_su[63:32];
      end
      ALU_MULHU: begin
        alu_res_o = mul_uu[63:32];
      end

      // ── RV32M — Divide / Remainder ─────────────────────────────────────────
      // All four obey the RISC-V spec for divide-by-zero and signed overflow.
      ALU_DIV: begin
        if (div_by_zero)          alu_res_o = ALL_ONES;   // spec: -1
        else if (signed_overflow) alu_res_o = INT_MIN;    // spec: INT_MIN
        else                      alu_res_o = $signed(op_a_i) / $signed(op_b_i);
      end
      ALU_DIVU: begin
        if (div_by_zero)          alu_res_o = ALL_ONES;   // spec: 2^32-1
        else                      alu_res_o = op_a_i / op_b_i;
      end
      ALU_REM: begin
        if (div_by_zero)          alu_res_o = op_a_i;     // spec: dividend
        else if (signed_overflow) alu_res_o = 32'b0;      // spec: 0
        else                      alu_res_o = $signed(op_a_i) % $signed(op_b_i);
      end
      ALU_REMU: begin
        if (div_by_zero)          alu_res_o = op_a_i;     // spec: dividend
        else                      alu_res_o = op_a_i % op_b_i;
      end

    endcase
  end

endmodule
