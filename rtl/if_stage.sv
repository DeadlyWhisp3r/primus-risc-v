`timescale 1ns / 1ps
import primus_core_pkg::*;

module if_stage (
  input logic         clk_i,
  input logic         rst_ni,    // Active low reset
  // Flush the pipeline, usually a branch taken -> grabage in the pipe
  input logic         pipeline_flush_i,
  input logic [31:0]  pc_i,      // Program counter

  // Port B — bootloader writes new program into instruction memory
  input logic         imem_we_b_i,
  input logic [9:0]   imem_addr_b_i,   // word-aligned (byte_addr[11:2])
  input logic [31:0]  imem_data_b_i,

  // writer interface
  output logic [31:0] ir_o,      // Instruction register
  output logic [31:0] pc_o,      // Current PC (for branch/jump target calculation)
  output logic [31:0] npc_o      // Next program counter (PC+4)

);

  logic [31:0] pc_d, pc_q, ir_d, ir_q, npc_d, npc_q;

  // Instruction memory — True Dual-Port BRAM
  // Port A: instruction fetch (read-only, used by IF stage)
  // Port B: bootloader write port (write-only, driven from top-level)
  xpm_memory_tdpram #(
    .ADDR_WIDTH_A        (10),              // 1024 words
    .ADDR_WIDTH_B        (10),
    .CLOCKING_MODE       ("common_clock"),  // single clock domain
    .MEMORY_PRIMITIVE    ("block"),
    .MEMORY_SIZE         (32768),           // 1024 * 32 bits
    .READ_DATA_WIDTH_A   (32),
    .READ_DATA_WIDTH_B   (32),
    .WRITE_DATA_WIDTH_A  (32),
    .WRITE_DATA_WIDTH_B  (32),
    .READ_LATENCY_A      (1),
    .READ_LATENCY_B      (1),
    .MEMORY_INIT_FILE    ("instructions.mem"),
    .MEMORY_INIT_PARAM   ("0"),
    .USE_MEM_INIT        (1)
  ) a_inst_mem (
    // Port A — fetch (read-only)
    .clka           (clk_i),
    .rsta           (~rst_ni),
    .ena            (1'b1),
    .wea            (1'b0),
    .addra          (pc_d[11:2]),
    .dina           (32'b0),
    .douta          (ir_d),
    .regcea         (1'b1),
    .injectdbiterra (1'b0),
    .injectsbiterra (1'b0),
    .dbiterra       (),
    .sbiterra       (),
    // Port B — bootloader write
    .clkb           (clk_i),
    .rstb           (~rst_ni),
    .enb            (1'b1),
    .web            (imem_we_b_i),
    .addrb          (imem_addr_b_i),
    .dinb           (imem_data_b_i),
    .doutb          (),                     // unused — we never read via Port B
    .regceb         (1'b1),
    .injectdbiterrb (1'b0),
    .injectsbiterrb (1'b0),
    .dbiterrb       (),
    .sbiterrb       (),
    .sleep          (1'b0)
  );

  // input assignments
  assign pc_d    = pc_i;

  // output assignments
  assign ir_o    = ir_d; //BRAM already clocked and otherwise the data is already gone
  assign pc_o    = pc_q;
  assign npc_o   = npc_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni) begin
      pc_q  <= '0;
      ir_q  <= 32'h00000013; // Resets to NOP
      npc_q <= '0;
    end else begin
      pc_q  <= pc_d;
      npc_q <= npc_d;
      // On pipeline flush insert a NOP to squash the speculatively fetched instruction
      ir_q  <= pipeline_flush_i ? 32'h00000013 : ir_d;
    end
  end

  always_comb begin
    npc_d = pc_d + 4; // Progress to next PC
  end

endmodule 
