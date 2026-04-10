`timescale 1ns / 1ps
import primus_core_pkg::*;
//
// rv32m_ls_tb.sv
//
// Unit tests for:
//   1. RV32M — MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU
//              including all RISC-V spec edge cases (divide-by-zero, INT_MIN/-1)
//   2. Load/store width — store byte-enable generation (SB/SH/SW)
//                         load sign/zero extension     (LB/LBU/LH/LHU/LW)
//
// Strategy:
//   ex_alu  outputs are purely combinational — drive inputs, #1, read result.
//   mem_stage load data is registered        — drive inputs, @(posedge clk), #1, read result.
//   mem_stage store outputs (wbe/wdata) are  combinational — drive inputs, #1, read result.
//

module rv32m_ls_tb();

  // ── shared infrastructure ─────────────────────────────────────────────────
  int pass_count = 0;
  int fail_count = 0;

  task automatic check(
    input string      name,
    input logic [31:0] got,
    input logic [31:0] expected
  );
    if (got === expected) begin
      $display("  PASS  %-30s = 0x%08X", name, got);
      pass_count++;
    end else begin
      $display("  FAIL  %-30s   got 0x%08X, expected 0x%08X", name, got, expected);
      fail_count++;
    end
  endtask

  // ── ex_alu instance ───────────────────────────────────────────────────────
  alu_op_e     alu_op;
  logic [31:0] op_a, op_b, alu_res;

  ex_alu dut_alu (
    .alu_op_i  (alu_op),
    .op_a_i    (op_a),
    .op_b_i    (op_b),
    .alu_res_o (alu_res)
  );

  // ── mem_stage instance ────────────────────────────────────────────────────
  logic        clk = 0;
  logic        rst_n;
  logic [31:0] mem_alu_res;
  logic [31:0] mem_rs2_data;
  logic        mem_ram_we;
  mem_op_e     mem_mem_op;
  logic [31:0] mem_ram_rdata;
  logic [31:0] mem_ram_addr;
  logic [31:0] mem_ram_wdata;
  logic [3:0]  mem_ram_wbe;
  logic [31:0] mem_wb_rdata;
  logic [31:0] mem_wb_alu_res;
  logic [31:0] mem_npc_out;
  logic [4:0]  mem_wb_rd_addr;
  logic        mem_wb_we;
  wb_sel_e     mem_wb_sel_out;

  always #5 clk = ~clk;  // 100 MHz

  mem_stage dut_mem (
    .clk_i            (clk),
    .rst_ni           (rst_n),
    .pipeline_flush_i (1'b0),
    .mem_npc_i        (32'b0),
    .mem_wb_sel_i     (WB_MEM),
    .mem_alu_res_i    (mem_alu_res),
    .mem_rs2_data_i   (mem_rs2_data),
    .mem_rd_addr_i    (5'b0),
    .mem_ram_we_i     (mem_ram_we),
    .mem_mem_op_i     (mem_mem_op),
    .mem_reg_we_i     (1'b1),
    .mem_ram_rdata_i  (mem_ram_rdata),
    .mem_ram_addr_o   (mem_ram_addr),
    .mem_ram_wdata_o  (mem_ram_wdata),
    .mem_ram_wbe_o    (mem_ram_wbe),
    .mem_wb_rdata_o   (mem_wb_rdata),
    .mem_wb_alu_res_o (mem_wb_alu_res),
    .mem_npc_o        (mem_npc_out),
    .mem_wb_rd_addr_o (mem_wb_rd_addr),
    .mem_wb_we_o      (mem_wb_we),
    .mem_wb_sel_o     (mem_wb_sel_out)
  );

  // ── test body ─────────────────────────────────────────────────────────────
  initial begin
    rst_n = 0;
    repeat(4) @(posedge clk);
    rst_n = 1;
    @(posedge clk);

    // =========================================================================
    // 1. RV32M — MULTIPLY
    // =========================================================================
    $display("\n=== RV32M: MUL (lower 32 bits) ===");

    // Basic: 6 * 7 = 42
    alu_op = ALU_MUL; op_a = 32'd6; op_b = 32'd7; #1;
    check("MUL 6*7", alu_res, 32'd42);

    // Lower 32 of large product: 0xFFFFFFFF * 0xFFFFFFFF = 0xFFFFFFFE_00000001
    alu_op = ALU_MUL; op_a = 32'hFFFFFFFF; op_b = 32'hFFFFFFFF; #1;
    check("MUL 0xFFFFFFFF*0xFFFFFFFF low", alu_res, 32'h00000001);

    // Signed negative: -1 * -1 = 1
    alu_op = ALU_MUL; op_a = 32'hFFFFFFFF; op_b = 32'hFFFFFFFF; #1;
    check("MUL (-1)*(-1) low", alu_res, 32'h00000001);

    $display("\n=== RV32M: MULH (signed * signed, upper 32) ===");

    // 0x80000000 * 0x80000000 = 0x4000000000000000 → upper = 0x40000000
    alu_op = ALU_MULH; op_a = 32'h80000000; op_b = 32'h80000000; #1;
    check("MULH INT_MIN*INT_MIN", alu_res, 32'h40000000);

    // -1 * -1 = 1 → upper = 0x00000000
    alu_op = ALU_MULH; op_a = 32'hFFFFFFFF; op_b = 32'hFFFFFFFF; #1;
    check("MULH (-1)*(-1) upper", alu_res, 32'h00000000);

    // -1 * 1 = -1 → upper = 0xFFFFFFFF
    alu_op = ALU_MULH; op_a = 32'hFFFFFFFF; op_b = 32'h00000001; #1;
    check("MULH (-1)*(1) upper", alu_res, 32'hFFFFFFFF);

    $display("\n=== RV32M: MULHSU (signed * unsigned, upper 32) ===");

    // -1 * 1 (unsigned) = 0xFFFFFFFF * 1 = 0x00000000_FFFFFFFF → upper = 0xFFFFFFFF
    alu_op = ALU_MULHSU; op_a = 32'hFFFFFFFF; op_b = 32'h00000001; #1;
    check("MULHSU (-1)*1u upper", alu_res, 32'hFFFFFFFF);

    // 1 * 0xFFFFFFFF (unsigned) = 0x00000000_FFFFFFFF → upper = 0x00000000
    alu_op = ALU_MULHSU; op_a = 32'h00000001; op_b = 32'hFFFFFFFF; #1;
    check("MULHSU 1*(0xFFFFFFFF)u upper", alu_res, 32'h00000000);

    $display("\n=== RV32M: MULHU (unsigned * unsigned, upper 32) ===");

    // 0xFFFFFFFF * 0xFFFFFFFF = 0xFFFFFFFE00000001 → upper = 0xFFFFFFFE
    alu_op = ALU_MULHU; op_a = 32'hFFFFFFFF; op_b = 32'hFFFFFFFF; #1;
    check("MULHU 0xFFFFFFFF*0xFFFFFFFF upper", alu_res, 32'hFFFFFFFE);

    // =========================================================================
    // 2. RV32M — DIVIDE
    // =========================================================================
    $display("\n=== RV32M: DIV (signed) ===");

    // 42 / 6 = 7
    alu_op = ALU_DIV; op_a = 32'd42; op_b = 32'd6; #1;
    check("DIV 42/6", alu_res, 32'd7);

    // -42 / 6 = -7 (0xFFFFFFF9)
    alu_op = ALU_DIV; op_a = -32'sd42; op_b = 32'sd6; #1;
    check("DIV -42/6", alu_res, 32'hFFFFFFF9);

    // -42 / -6 = 7
    alu_op = ALU_DIV; op_a = -32'sd42; op_b = -32'sd6; #1;
    check("DIV -42/-6", alu_res, 32'd7);

    // Spec: divide by zero → -1 (all ones)
    alu_op = ALU_DIV; op_a = 32'd42; op_b = 32'd0; #1;
    check("DIV by zero", alu_res, 32'hFFFFFFFF);

    // Spec: signed overflow (INT_MIN / -1) → INT_MIN
    alu_op = ALU_DIV; op_a = 32'h80000000; op_b = 32'hFFFFFFFF; #1;
    check("DIV INT_MIN/-1 (overflow)", alu_res, 32'h80000000);

    $display("\n=== RV32M: DIVU (unsigned) ===");

    // 10 / 3 = 3
    alu_op = ALU_DIVU; op_a = 32'd10; op_b = 32'd3; #1;
    check("DIVU 10/3", alu_res, 32'd3);

    // Spec: divide by zero → 2^32-1 (all ones)
    alu_op = ALU_DIVU; op_a = 32'd42; op_b = 32'd0; #1;
    check("DIVU by zero", alu_res, 32'hFFFFFFFF);

    // 0xFFFFFFFF / 2 = 0x7FFFFFFF
    alu_op = ALU_DIVU; op_a = 32'hFFFFFFFF; op_b = 32'd2; #1;
    check("DIVU 0xFFFFFFFF/2", alu_res, 32'h7FFFFFFF);

    // =========================================================================
    // 3. RV32M — REMAINDER
    // =========================================================================
    $display("\n=== RV32M: REM (signed) ===");

    // 10 % 3 = 1
    alu_op = ALU_REM; op_a = 32'd10; op_b = 32'd3; #1;
    check("REM 10%3", alu_res, 32'd1);

    // -10 % 3 = -1 (sign follows dividend in RISC-V)
    alu_op = ALU_REM; op_a = -32'sd10; op_b = 32'sd3; #1;
    check("REM -10%3", alu_res, 32'hFFFFFFFF);

    // 10 % -3 = 1 (sign follows dividend)
    alu_op = ALU_REM; op_a = 32'sd10; op_b = -32'sd3; #1;
    check("REM 10%-3", alu_res, 32'd1);

    // Spec: remainder by zero → dividend
    alu_op = ALU_REM; op_a = 32'd99; op_b = 32'd0; #1;
    check("REM by zero", alu_res, 32'd99);

    // Spec: signed overflow (INT_MIN % -1) → 0
    alu_op = ALU_REM; op_a = 32'h80000000; op_b = 32'hFFFFFFFF; #1;
    check("REM INT_MIN%-1 (overflow)", alu_res, 32'd0);

    $display("\n=== RV32M: REMU (unsigned) ===");

    // 10 % 3 = 1
    alu_op = ALU_REMU; op_a = 32'd10; op_b = 32'd3; #1;
    check("REMU 10%3", alu_res, 32'd1);

    // Spec: remainder by zero → dividend
    alu_op = ALU_REMU; op_a = 32'd77; op_b = 32'd0; #1;
    check("REMU by zero", alu_res, 32'd77);

    // 0xFFFFFFFF % 2 = 1
    alu_op = ALU_REMU; op_a = 32'hFFFFFFFF; op_b = 32'd2; #1;
    check("REMU 0xFFFFFFFF%2", alu_res, 32'd1);

    // =========================================================================
    // 4. Store byte-enable and write-data generation
    //    These are combinational outputs — check immediately after #1.
    // =========================================================================
    $display("\n=== Store: byte-enable and write-data generation ===");
    mem_ram_we = 1;

    // SW — full word, wbe = 4'b1111, wdata unchanged
    mem_alu_res = 32'h1000; mem_rs2_data = 32'hDEADBEEF; mem_mem_op = MEM_W; #1;
    check("SW wbe",         {28'b0, mem_ram_wbe}, 32'hF);
    check("SW wdata",       mem_ram_wdata,         32'hDEADBEEF);

    // SB at byte lane 0 (addr[1:0]=00) → wbe=0001, byte replicated to all lanes
    mem_alu_res = 32'h1000; mem_rs2_data = 32'hABCDABFF; mem_mem_op = MEM_B; #1;
    check("SB[0] wbe",      {28'b0, mem_ram_wbe},  32'h1);
    check("SB[0] wdata[7:0]", {24'b0, mem_ram_wdata[7:0]}, 32'hFF);

    // SB at byte lane 1 (addr[1:0]=01) → wbe=0010
    mem_alu_res = 32'h1001; mem_rs2_data = 32'hABCDABAB; mem_mem_op = MEM_B; #1;
    check("SB[1] wbe",      {28'b0, mem_ram_wbe},  32'h2);

    // SB at byte lane 2 (addr[1:0]=10) → wbe=0100
    mem_alu_res = 32'h1002; mem_rs2_data = 32'hABCDABAB; mem_mem_op = MEM_B; #1;
    check("SB[2] wbe",      {28'b0, mem_ram_wbe},  32'h4);

    // SB at byte lane 3 (addr[1:0]=11) → wbe=1000
    mem_alu_res = 32'h1003; mem_rs2_data = 32'hABCDABAB; mem_mem_op = MEM_B; #1;
    check("SB[3] wbe",      {28'b0, mem_ram_wbe},  32'h8);

    // SH at halfword 0 (addr[1]=0) → wbe=0011, lower halfword replicated
    mem_alu_res = 32'h1000; mem_rs2_data = 32'hABCD1234; mem_mem_op = MEM_H; #1;
    check("SH[0] wbe",           {28'b0, mem_ram_wbe},   32'h3);
    check("SH[0] wdata[15:0]",   {16'b0, mem_ram_wdata[15:0]}, 32'h1234);

    // SH at halfword 2 (addr[1]=1) → wbe=1100, halfword in upper lanes
    mem_alu_res = 32'h1002; mem_rs2_data = 32'hABCD5678; mem_mem_op = MEM_H; #1;
    check("SH[2] wbe",           {28'b0, mem_ram_wbe},   32'hC);
    check("SH[2] wdata[31:16]",  {16'b0, mem_ram_wdata[31:16]}, 32'h5678);

    // =========================================================================
    // 5. Load sign/zero extension
    //    mem_wb_rdata_o is registered — set inputs then wait one clock edge.
    // =========================================================================
    $display("\n=== Load: sign/zero extension ===");
    mem_ram_we = 0;

    // LW — full word passes through unchanged
    mem_alu_res = 32'h1000; mem_ram_rdata = 32'hDEADBEEF; mem_mem_op = MEM_W;
    @(posedge clk); #1;
    check("LW",              mem_wb_rdata, 32'hDEADBEEF);

    // LB byte lane 0: rdata[7:0]=0xFF → sign-extended 0xFFFFFFFF
    mem_alu_res = 32'h1000; mem_ram_rdata = 32'hABCD12FF; mem_mem_op = MEM_B;
    @(posedge clk); #1;
    check("LB  byte0 0xFF", mem_wb_rdata, 32'hFFFFFFFF);

    // LB byte lane 1: rdata[15:8]=0x12 → sign-extended 0x00000012
    mem_alu_res = 32'h1001; mem_ram_rdata = 32'hABCD12FF; mem_mem_op = MEM_B;
    @(posedge clk); #1;
    check("LB  byte1 0x12", mem_wb_rdata, 32'h00000012);

    // LB byte lane 2: rdata[23:16]=0xCD → sign-extended 0xFFFFFFCD
    mem_alu_res = 32'h1002; mem_ram_rdata = 32'hABCD12FF; mem_mem_op = MEM_B;
    @(posedge clk); #1;
    check("LB  byte2 0xCD", mem_wb_rdata, 32'hFFFFFFCD);

    // LBU byte lane 0: rdata[7:0]=0xFF → zero-extended 0x000000FF
    mem_alu_res = 32'h1000; mem_ram_rdata = 32'hABCD12FF; mem_mem_op = MEM_BU;
    @(posedge clk); #1;
    check("LBU byte0 0xFF", mem_wb_rdata, 32'h000000FF);

    // LBU byte lane 1: rdata[15:8]=0x12 → zero-extended 0x00000012
    mem_alu_res = 32'h1001; mem_ram_rdata = 32'hABCD12FF; mem_mem_op = MEM_BU;
    @(posedge clk); #1;
    check("LBU byte1 0x12", mem_wb_rdata, 32'h00000012);

    // LH halfword 0: rdata[15:0]=0x8000 → sign-extended 0xFFFF8000
    mem_alu_res = 32'h1000; mem_ram_rdata = 32'hABCD8000; mem_mem_op = MEM_H;
    @(posedge clk); #1;
    check("LH  half0 0x8000", mem_wb_rdata, 32'hFFFF8000);

    // LH halfword 2: rdata[31:16]=0xABCD → sign-extended 0xFFFFABCD
    mem_alu_res = 32'h1002; mem_ram_rdata = 32'hABCD8000; mem_mem_op = MEM_H;
    @(posedge clk); #1;
    check("LH  half2 0xABCD", mem_wb_rdata, 32'hFFFFABCD);

    // LH halfword 0 positive: rdata[15:0]=0x7FFF → sign-extended 0x00007FFF
    mem_alu_res = 32'h1000; mem_ram_rdata = 32'h00007FFF; mem_mem_op = MEM_H;
    @(posedge clk); #1;
    check("LH  half0 0x7FFF", mem_wb_rdata, 32'h00007FFF);

    // LHU halfword 0: rdata[15:0]=0x8000 → zero-extended 0x00008000
    mem_alu_res = 32'h1000; mem_ram_rdata = 32'hABCD8000; mem_mem_op = MEM_HU;
    @(posedge clk); #1;
    check("LHU half0 0x8000", mem_wb_rdata, 32'h00008000);

    // LHU halfword 2: rdata[31:16]=0xABCD → zero-extended 0x0000ABCD
    mem_alu_res = 32'h1002; mem_ram_rdata = 32'hABCD8000; mem_mem_op = MEM_HU;
    @(posedge clk); #1;
    check("LHU half2 0xABCD", mem_wb_rdata, 32'h0000ABCD);

    // ── Summary ──────────────────────────────────────────────────────────────
    $display("\n========================================");
    $display("Results: %0d passed, %0d failed", pass_count, fail_count);
    if (fail_count == 0) $display("ALL TESTS PASSED");
    else                 $display("FAILURES DETECTED");
    $display("========================================");
    $finish;
  end

  // Global timeout
  initial begin
    #1_000_000;
    $display("GLOBAL TIMEOUT");
    $finish;
  end

endmodule
