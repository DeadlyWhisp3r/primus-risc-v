`timescale 1ns / 1ps
import primus_core_pkg::*;

module id_stage_tb;

  // Variables used for stimuli
  logic clk;
  logic rst_n;
  logic [31:0] npc_i;
  logic [31:0] instr_i;
  logic [31:0] wb_w_addr_i;
  logic [31:0] wb_w_data_i;
  logic        wb_we_i;

  logic [31:0] id_rs1_o;
  logic [31:0] id_rs2_o;
  logic [31:0] npc_o;
  logic [31:0] imm_o;
  ctrl_t id_ctrl_o;

  // Variable for the instructions loaded from textfile
  logic [31:0] test_mem [0:15];
  integer i;

  // Define clk
  always #10 clk = ~clk;

  // Instantiate the DUT and connect the stimuli above
  id_stage a_id_stage(
    .clk_i       (clk),
    .rst_ni      (rst_n),
    .npc_i       (npc_i), 
    .instr_i     (instr_i),
    .wb_w_addr_i (wb_w_addr_i),
    .wb_w_data_i (wb_w_data_i),
    .wb_we_i     (wb_we_i),
    .id_rs1_o    (id_rs1_o),
    .id_rs2_o    (id_rs2_o),
    .npc_o       (npc_o),
    .imm_o       (imm_o),
    .id_ctrl_o   (id_ctrl_o)
  );

  // Define the stimuli for the test
  // Since we just want to check a submodule we will
  // Have a simpler stimuli and no scoreboard, monitor,etc
  initial begin
    // --- 1. Initialize Inputs ---
    clk         = 0;
    rst_n       = 0;
    instr_i     = 32'h00000013; // Start with a NOP (addi x0, x0, 0)
    npc_i       = 0;
    wb_w_addr_i = 0;
    wb_w_data_i = 0;
    wb_we_i     = 0;

    // --- 2. Load the Instruction File ---
    // Ensure "instr.hex" is in the same folder as your simulation
    $readmemh("instr.hex", test_mem);

    // Release Reset
    #25 rst_n = 1; 

    // --- 3. Pre-fill Register File (Optional but Helpful) ---
    // This allows you to see if rs1_o and rs2_o actually output data
    @(negedge clk);
    wb_w_addr_i = 5;       // Write to register x5
    wb_w_data_i = 32'hAAAA_BBBB;
    wb_we_i     = 1;

    @(negedge clk);
    wb_w_addr_i = 6;       // Write to register x6
    wb_w_data_i = 32'h1234_5678;
    wb_we_i     = 1;

    @(negedge clk);
    wb_w_addr_i = 0;       // Stop writing

    // --- 4. Loop Through the Instructions ---
    for (i = 0; i < 15; i += 1) begin
      @(negedge clk);      // Drive inputs on the falling edge for stability
      instr_i = test_mem[i];
      npc_i   += 4;     // Simulate the PC incrementing
      
      // Print to the console for easier debugging
      $display("Time: %0t | PC: %h | Decoding: %h", $time, npc_i, instr_i);
    end

    #100;
    $display("Testbench finished successfully.");
    $finish;
  end

  // Dumping the simulation waveform
  initial begin
    $dumpvars;
    $dumpfile("dump.vcd");
  end

  // Assign program counter to next program counter
  assign pc_i = npc_o;
endmodule
