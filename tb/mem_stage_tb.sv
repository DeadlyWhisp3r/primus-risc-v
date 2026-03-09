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
    logic [4:0]   mem_rd_addr_i;
    logic         mem_ram_we_i; // Specifically for Data RAM (Stores)
    logic         mem_we_i;     // Specifically for WB Stage (Reg Write)

    // Memory Interface (Top level connections)
    logic [31:0] dmem_rdata;
    logic [31:0] dmem_addr, dmem_wdata;
    logic        dmem_we;

    // Outputs from MEM Stage (going to WB)
    logic [31:0] mem_wb_rdata_o, mem_wb_alu_res_o;
    logic [4:0]  mem_wb_rd_addr_o;
    logic        mem_wb_we_o;
    wb_sel_e     mem_wb_sel_o;

    // UUT Instance
    mem_stage uut (
        .clk_i                (clk_i),
        .rst_ni               (rst_ni),
        .mem_wb_sel_i         (mem_wb_sel_i),
        .mem_alu_res_i        (mem_alu_res_i),
        .mem_rs2_data_i       (mem_rs2_data_i),
        .mem_rd_addr_i        (mem_rd_addr_i),
        .mem_ram_we_i         (mem_ram_we_i), // Correctly mapped to RAM input
        .mem_we_i             (mem_we_i),     // Correctly mapped to WB input
        .mem_ram_addr_o       (dmem_addr),
        .mem_ram_wdata_o      (dmem_wdata),
        .mem_ram_we_o         (dmem_we),
        .mem_ram_rdata_i      (dmem_rdata),
        .mem_wb_rdata_o       (mem_wb_rdata_o),
        .mem_wb_alu_res_o      (mem_wb_alu_res_o),
        .mem_wb_rd_addr_o      (mem_wb_rd_addr_o),
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
        mem_rd_addr_i  <= rd_addr;
        mem_ram_we_i   <= ram_we;   // Drive RAM enable
        mem_we_i       <= reg_we;   // Drive WB enable
        dmem_rdata     <= fake_ram_data; 

        @(posedge clk_i); // Cycle 1: Values latched into _q registers
        #1;
        $display("[%s] @MEM: RAM_Addr=%h, RAM_WE=%b, RAM_WData=%h", name, dmem_addr, dmem_we, dmem_wdata);
        
        @(posedge clk_i); // Cycle 2: Values appear at WB outputs
        #1;
        $display("[%s] @WB:  RData=%h, ALU_Res=%h, RD=%d, RegWE=%b", name, mem_wb_rdata_o, mem_wb_alu_res_o, mem_wb_rd_addr_o, mem_wb_we_o);
    endtask

    initial begin
        // Reset and initialization
        rst_ni = 0;
        mem_wb_sel_i   = WB_ALU;
        mem_alu_res_i  = 0;
        mem_rs2_data_i = 0;
        mem_rd_addr_i  = 0;
        mem_ram_we_i   = 0;
        mem_we_i       = 0;
        dmem_rdata     = 0;

        #20; rst_ni = 1;

        // --- 1. STORE TEST ---
        // ram_we = 1 (to save to memory), reg_we = 0 (stores don't write to x registers)
        $display("--- 1. STORE TEST ---");
        drive_mem(WB_ALU, 32'h40, 32'hDEAD_BEEF, 5'd0, 1'b1, 1'b0, 32'h0, "STORE_W");

        // --- 2. LOAD TEST ---
        // ram_we = 0, reg_we = 1 (loads write to x registers)
        $display("--- 2. LOAD TEST ---");
        drive_mem(WB_MEM, 32'h40, 32'h0, 5'd10, 1'b0, 1'b1, 32'hCAFE_BABE, "LOAD_W");

        // --- 3. ALU PASS-THROUGH ---
        // ram_we = 0, reg_we = 1 (arithmetic writes to x registers)
        $display("--- 3. ALU PASS-THROUGH ---");
        drive_mem(WB_ALU, 32'h100, 32'h0, 5'd15, 1'b0, 1'b1, 32'h0, "ALU_OP");

        #50 $finish;
    end
endmodule
