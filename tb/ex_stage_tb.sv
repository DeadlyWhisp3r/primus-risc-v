`timescale 1ns / 1ps
import primus_core_pkg::*;

module ex_stage_tb();

    logic clk_i = 0;
    logic rst_ni;

    // Inputs
    logic [31:0] ex_npc_i, ex_rs1_i, ex_rs2_i, ex_imm_i;
    logic [4:0]  ex_rd_addr_i;
    ctrl_t       ex_ctrl_i;

    // Outputs
    logic [31:0] ex_npc_o, ex_target_pc_o, ex_alu_res_o;
    logic        ex_pc_sel_o, ex_reg_write_o, ex_pipeline_flush_o;
    logic [4:0]  ex_rd_addr_o;
    wb_sel_e     ex_wb_sel_o;

    ex_stage a_ex_stage (
        .clk_i               (clk_i),
        .rst_ni              (rst_ni),
        .ex_npc_i            (ex_npc_i),
        .ex_rs1_i            (ex_rs1_i),
        .ex_rs2_i            (ex_rs2_i),
        .ex_rd_addr_i        (ex_rd_addr_i),
        .ex_imm_i            (ex_imm_i),
        .ex_ctrl_i           (ex_ctrl_i),
        .ex_npc_o            (ex_npc_o),
        .ex_pc_sel_o         (ex_pc_sel_o),
        .ex_target_pc_o      (ex_target_pc_o),
        .ex_alu_res_o        (ex_alu_res_o),
        .ex_rd_addr_o        (ex_rd_addr_o),
        .ex_reg_write_o      (ex_reg_write_o),
        .ex_pipeline_flush_o (ex_pipeline_flush_o),
        .ex_wb_sel_o         (ex_wb_sel_o)
    );

    always #5 clk_i = ~clk_i;

    // Universal Task to drive and verify any Execute Stage instruction
    task drive_instr(
        input alu_op_e    alu_op,   // ALU Operation (ADD, SUB, SLL, etc.)
        input br_op_e     br_op,    // Branch Condition (BEQ, BNE, etc.)
        input logic       is_br,    // Instruction is a Branch
        input logic       is_jmp,   // Instruction is a Jump (JAL/JALR)
        input alu_a_sel_e a_sel,    // Operand A Mux: 0 for RS1, 1 for PC
        input alu_b_sel_e b_sel,    // Operand B Mux: 0 for RS2, 1 for IMM
        input [31:0]      rs1,      // Register Source 1 Value
        input [31:0]      rs2,      // Register Source 2 Value
        input [31:0]      imm,      // Immediate Value
        input [31:0]      npc,      // Next PC (usually PC + 4)
        input [31:0]      exp_alu,  // Expected ALU Result
        input logic       exp_pc_sel,// Expected PC Select (Branch Taken/Jump)
        input string      name      // Test Case Description
    );
        @(posedge clk_i);
        // --- 1. Drive Inputs to the pipeline registers (_d side) ---
        ex_ctrl_i.alu_op    <= alu_op;
        ex_ctrl_i.alu_br_op <= br_op;
        ex_ctrl_i.is_branch <= is_br;
        ex_ctrl_i.is_jump   <= is_jmp;
        ex_ctrl_i.alu_a_sel <= a_sel;
        ex_ctrl_i.alu_b_sel <= b_sel;

        ex_rs1_i            <= rs1;
        ex_rs2_i            <= rs2;
        ex_imm_i            <= imm;
        ex_npc_i            <= npc;

        // --- 2. Wait for the Clock Edge ---
        // This moves the data from the input pins into the _q registers
        @(posedge clk_i); 

        // --- 3. Verify Outputs (_q side) ---
        #1; // Small safety delay to let signals settle in simulation

        if (ex_alu_res_o !== exp_alu || ex_pc_sel_o !== exp_pc_sel) begin
            $display("FAIL [%s]:", name);
            $display("  > ALU Result: Got %h, Expected %h", ex_alu_res_o, exp_alu);
            $display("  > PC Select:  Got %b, Expected %b", ex_pc_sel_o, exp_pc_sel);
        end else begin
            $display("PASS [%s]", name);
        end
    endtask

    initial begin
        // Reset sequence
        rst_ni = 0;
        ex_ctrl_i = '0;
        ex_rs1_i = 0; ex_rs2_i = 0; ex_imm_i = 0; ex_npc_i = 0;
        #20 rst_ni = 1;

        // --- 1. ARITHMETIC & LOGIC ---
        $display("--- 1. ARITHMETIC & LOGIC ---");
        // drive_instr(alu_op, br_op, is_br, is_jmp, a_sel, b_sel, rs1, rs2, imm, npc, exp_alu, exp_pc, name)
        drive_instr(ALU_ADD, BR_NONE, 0, 0, 0, 1, 32'hA, 0, 32'h5, 0, 32'hF, 0, "ADD");
        drive_instr(ALU_SUB, BR_NONE, 0, 0, 0, 1, 32'hA, 0, 32'h5, 0, 32'h5, 0, "SUB");
        drive_instr(ALU_AND, BR_NONE, 0, 0, 0, 1, 32'hFFFF_0000, 0, 32'hFF00_FF00, 0, 32'hFF00_0000, 0, "AND");
        drive_instr(ALU_OR,  BR_NONE, 0, 0, 0, 1, 32'hAAAA_0000, 0, 32'h0000_5555, 0, 32'hAAAA_5555, 0, "OR");
        drive_instr(ALU_XOR, BR_NONE, 0, 0, 0, 1, 32'hF0F0_F0F0, 0, 32'hFFFF_FFFF, 0, 32'h0F0F_0F0F, 0, "XOR");

        // --- 2. SHIFTS ---
        $display("--- 2. SHIFTS (5-bit Mask) ---");
        drive_instr(ALU_SLL, BR_NONE, 0, 0, 0, 1, 32'h1, 0, 32'd4, 0, 32'h10, 0, "SLL");
        drive_instr(ALU_SRL, BR_NONE, 0, 0, 0, 1, 32'h8000_0000, 0, 32'd1, 0, 32'h4000_0000, 0, "SRL");
        drive_instr(ALU_SRA, BR_NONE, 0, 0, 0, 1, 32'h8000_0000, 0, 32'd1, 0, 32'hC000_0000, 0, "SRA");
        drive_instr(ALU_SLL, BR_NONE, 0, 0, 0, 1, 32'h1, 0, 32'd32, 0, 32'h1, 0, "SLL_MASK_32");

        // --- 3. COMPARISONS ---
        $display("--- 3. COMPARISONS ---");
        drive_instr(ALU_SLT,  BR_NONE, 0, 0, 0, 1, -32'd1, 0, 32'd1, 0, 32'h1, 0, "SLT_TRUE");
        drive_instr(ALU_SLTU, BR_NONE, 0, 0, 0, 1, -32'd1, 0, 32'd1, 0, 32'h0, 0, "SLTU_FALSE");
        drive_instr(ALU_COPY_B, BR_NONE, 0, 0, 0, 1, 32'hAAAA_BBBB, 0, 32'h1234_5678, 0, 32'h1234_5678, 0, "COPY_B");

        // --- 4. BRANCHES ---
        $display("--- 4. BRANCHES (BEQ, BNE, BLT, BGE, BLTU, BGEU) ---");
        // For branches, we check if pc_sel_o becomes 1. exp_alu is the target PC calculation.
        drive_instr(ALU_ADD, BR_EQ,  1, 0, 1, 1, 32'd10, 32'd10, 32'h4, 32'h1000, 32'h1004, 1, "BEQ_T");
        drive_instr(ALU_ADD, BR_NE,  1, 0, 1, 1, 32'd10, 32'd11, 32'h4, 32'h1000, 32'h1004, 1, "BNE_T");
        drive_instr(ALU_ADD, BR_LT,  1, 0, 1, 1, -32'd5, 32'd1,  32'h4, 32'h1000, 32'h1004, 1, "BLT_T");
        drive_instr(ALU_ADD, BR_GE,  1, 0, 1, 1, 32'd5,  32'd1,  32'h4, 32'h1000, 32'h1004, 1, "BGE_T");
        drive_instr(ALU_ADD, BR_LTU, 1, 0, 1, 1, 32'd1, -32'd1,  32'h4, 32'h1000, 32'h1004, 1, "BLTU_T");
        drive_instr(ALU_ADD, BR_GEU, 1, 0, 1, 1, -32'd1, 32'd1,  32'h4, 32'h1000, 32'h1004, 1, "BGEU_T");

        // --- 5. JUMPS & SPECIALS ---
        $display("--- 5. JUMPS & SPECIALS (LUI, AUIPC, JAL, JALR) ---");
        // LUI: Ignore RS1, use Imm
        drive_instr(ALU_COPY_B, BR_NONE, 0, 0, 0, 1, 0, 0, 32'h1234_5000, 0, 32'h1234_5000, 0, "LUI");
        // AUIPC: PC + Imm
        drive_instr(ALU_ADD, BR_NONE, 0, 0, 1, 1, 0, 0, 32'h1000, 32'h4000, 32'h5000, 0, "AUIPC");
        // JAL: PC + Imm, pc_sel always 1
        drive_instr(ALU_ADD, BR_NONE, 0, 1, 1, 1, 0, 0, 32'h8, 32'h4000, 32'h4008, 1, "JAL_TARGET");
        // JALR: RS1 + Imm, pc_sel always 1
        drive_instr(ALU_ADD, BR_NONE, 0, 1, 0, 1, 32'h6000, 0, 32'h4, 32'h4000, 32'h6004, 1, "JALR_TARGET");

        $display("--- ALL TESTS COMPLETE ---");
        #50 $finish;
    end
endmodule
