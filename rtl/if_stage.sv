`timescale 1ns / 1ps
import primus_core_pkg::*;

module if_stage (
  input logic         clk_i,
  input logic         rst_ni,    // Active low reset
  // Flush the pipeline, usually a branch taken -> grabage in the pipe
  input logic         pipeline_flush_i,
  input logic [31:0]  pc_i,      // Program counter

  // writer interface
  output logic [31:0] ir_o,      // Instruction register
  output logic [31:0] npc_o      // Next program counter

);

  logic [31:0] pc_d, pc_q, ir_d, ir_q, npc_d, npc_q;

  // Instantiate module instruction memory
  // XPM Single Port RAM for Instruction Memory
  xpm_memory_spram #(
    .ADDR_WIDTH_A        (10),              // 1024 words = 10 bits
    .MEMORY_PRIMITIVE    ("block"),         // Use BRAM
    .MEMORY_SIZE         (32768),           // 1024 words * 32 bits = 32768 bits
    .READ_DATA_WIDTH_A   (32),              // RISC-V Instruction width
    .READ_LATENCY_A      (1),               // 1 clock cycle latency
    .WRITE_DATA_WIDTH_A  (32),
    .MEMORY_INIT_FILE    ("instructions.mem"), // The file we created earlier
    .MEMORY_INIT_PARAM   ("0"),
    .USE_MEM_INIT        (1)                // Enable memory initialization
  ) a_inst_mem (
    .clka   (clk_i),
    .rsta   (~rst_ni),                      // Active high reset for XPM
    .ena    (1'b1),                         // Always enabled
    .wea    (1'b0),                         // Read-only
    .addra  (pc_d[11:2]),                   // Word-aligned address
    .dina   (32'b0),
    .douta  (ir_d),                         // Data out to Decode stage
    .regcea (1'b1),
    .injectdbiterra(1'b0),
    .injectsbiterra(1'b0),
    .sleep  (1'b0)
  );

  // input assignments
  assign pc_d    = pc_i;

  // output assignments
  assign ir_o    = ir_d; //BRAM already clocked and otherwise the data is already gone
  assign npc_o   = npc_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    // Active low reset and pipeline flush
    if(!rst_ni || pipeline_flush_i) begin
      pc_q  <= '0;
      ir_q  <= 32'h00000013; // Resets to NOP
      npc_q <= '0;
    end else begin
      pc_q  <= pc_d;
      ir_q  <= ir_d;
      npc_q <= npc_d;
    end
  end

  always_comb begin
    npc_d = pc_q + 4; // Progress to next PC
  end

endmodule 
