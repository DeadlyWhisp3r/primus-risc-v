`timescale 1ns / 1ps

module inst_fetch_tb;

  // Variables used for stimuli
  logic clk;
  logic rst_n;
  logic [31:0] pc_i;
  logic [31:0] ir_o;
  logic [31:0] npc_o;

  // Define clk
  always #10 clk = ~clk;

  // Instantiate the DUT and connect the stimuli above
  primus_instruction_fetch a_inst_fetch(
    .clk_i    (clk),
    .rst_ni   (rst_n),              // Active low reset
    .pc_i     (pc_i),               // Program counter 
    .ir_o     (ir_o),               // Instruction register
    .npc_o    (npc_o)               // Next program counter
  );

  // Define the stimuli for the test
  // Since we just want to check a submodule we will
  // Have a simpler stimuli and no scoreboard, monitor,etc
  initial begin
    clk       <= 0;
    rst_n     <= 0;
    #20 rst_n <= 1;

    #1000
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
