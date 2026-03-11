`timescale 1ns / 1ps
import primus_core_pkg::*;

module mem_stage_tb();

    // Clock and Reset
    logic clk_i = 0;
    logic rst_ni;

    // Inputs to MEM Stage (coming from EX)
    wb_sel_e      mem_wb_sel_i;
    logic [31:0]  mem_alu_res_i;
    logic [31:0]  mem_rs2_data_i;
    logic [31:0]  mem_npc_i;
    logic [4:0]   mem_rd_addr_i;
    logic         mem_ram_we_i; // Specifically for Data RAM (Stores)
    logic         mem_reg_we_i;     // Specifically for WB Stage (Reg Write)

    // Memory Interface (Top level connections)
    logic [31:0] dmem_rdata;
    logic [31:0] dmem_addr, dmem_wdata;
    logic        dmem_we;

    // Outputs from MEM Stage (going to WB)
    logic [31:0] mem_wb_rdata_o, mem_wb_alu_res_o, mem_npc_o;
    logic [4:0]  mem_wb_rd_addr_o;
    logic        mem_wb_we_o;
    wb_sel_e     mem_wb_sel_o;

    // UUT Instance
    mem_stage uut (
        .clk_i                (clk_i),
        .rst_ni               (rst_ni),
        .mem_npc_i            (mem_npc_i),
        .mem_wb_sel_i         (mem_wb_sel_i),
        .mem_alu_res_i        (mem_alu_res_i),
        .mem_rs2_data_i       (mem_rs2_data_i),
        .mem_rd_addr_i        (mem_rd_addr_i),
        .mem_ram_we_i         (mem_ram_we_i), // Correctly mapped to RAM input
        .mem_reg_we_i         (mem_reg_we_i),     // Correctly mapped to WB input
        .mem_ram_addr_o       (dmem_addr),
        .mem_ram_wdata_o      (dmem_wdata),
        .mem_ram_we_o         (dmem_we),
        .mem_ram_rdata_i      (dmem_rdata),
        .mem_wb_rdata_o       (mem_wb_rdata_o),
        .mem_wb_alu_res_o     (mem_wb_alu_res_o),
        .mem_npc_o            (mem_npc_o),
        .mem_wb_rd_addr_o     (mem_wb_rd_addr_o),
        .mem_wb_we_o          (mem_wb_we_o),
        .mem_wb_sel_o         (mem_wb_sel_o)
    );

    // Clock Gen
    always #5 clk_i = ~clk_i;

    // Updated Task to drive both write enables independently
    task drive_mem(
        input wb_sel_e wb_sel,
        input [31:0]   alu_res,
        input [31:0]   rs2_data,
        input [31:0]   npc,
        input [4:0]    rd_addr,
        input logic    ram_we,      // Controls RAM Store
        input logic    reg_we,      // Controls Register File Write
        input [31:0]   fake_ram_data,
        input string   name
    );
        @(posedge clk_i);
        mem_wb_sel_i   <= wb_sel;
        mem_alu_res_i  <= alu_res;
        mem_rs2_data_i <= rs2_data;
        mem_npc_i      <= npc;
        mem_rd_addr_i  <= rd_addr;
        mem_ram_we_i   <= ram_we;   // Drive RAM enable
        mem_reg_we_i   <= reg_we;   // Drive WB enable
        dmem_rdata     <= fake_ram_data; 

        @(posedge clk_i); // Cycle 1: Values latched into _q registers
        #1;
        $display("[%s] @MEM: RAM_Addr=%h, RAM_WE=%b, RAM_WData=%h", name, dmem_addr, dmem_we, dmem_wdata);
        
        @(posedge clk_i); // Cycle 2: Values appear at WB outputs
        #1;
        $display("[%s] @WB:  RData=%h, ALU_Res=%h, RD=%d, RegWE=%b", name, mem_wb_rdata_o, mem_wb_alu_res_o, mem_wb_rd_addr_o, mem_wb_we_o);
    endtask

    initial begin
        rst_ni = 0;
        mem_npc_i      = 0;
        mem_wb_sel_i   = WB_ALU;
        mem_alu_res_i  = 0;
        mem_rs2_data_i = 0;
        mem_rd_addr_i  = 0;
        mem_ram_we_i   = 0;
        mem_reg_we_i   = 0;
        dmem_rdata     = 0;

        #20; rst_ni = 1;

        $display("--- 1. STORE TEST ---");
        // For stores, NPC is just passed along (usually PC+4)
        drive_mem(WB_ALU, 32'h40, 32'hDEAD_BEEF, 32'h1004, 5'd0, 1'b1, 1'b0, 32'h0, "STORE_W");

        $display("--- 2. LOAD TEST ---");
        drive_mem(WB_MEM, 32'h40, 32'h0, 32'h1008, 5'd10, 1'b0, 1'b1, 32'hCAFE_BABE, "LOAD_W");

        $display("--- 3. JUMP TEST (Testing NPC pass-through) ---");
        // Here we simulate a JAL where WB_PC4 is selected
        drive_mem(WB_PC4, 32'h2000, 32'h0, 32'h100C, 5'd1, 1'b0, 1'b1, 32'h0, "JAL_OP");

        #50 $finish;
    end

endmodule
