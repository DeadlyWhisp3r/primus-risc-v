`timescale 1ns / 1ps
import primus_core_pkg::*;

module primus_risc_v_top(
  // Input for top module
  input  logic        clk_i,
  input  logic        rst_ni,
  // LED outputs: LED[7:0] = x1[7:0], LED[15:8] = x2[7:0]
  output logic [15:0] led_o
);


  // Instruction fetch signals
  logic [31:0]  pc;
  logic [31:0]  if_ir;
  logic [31:0]  if_pc;
  logic [31:0]  if_npc;

  // Instruction decode signals
  logic [31:0]  id_rs1;
  logic [31:0]  id_rs2;
  logic [4:0]   id_rs1_addr;
  logic [4:0]   id_rs2_addr;
  logic [4:0]   id_rd_addr;
  logic [31:0]  id_pc;
  logic [31:0]  id_npc;
  logic [31:0]  id_imm;
  ctrl_t        id_ctrl;

  // Branch predictor signals
  logic         id_predict_taken;
  logic         id_bp_taken;
  logic [31:0]  id_bp_target;
  logic         ex_br_taken;
  logic         ex_is_branch;

  // Execute stage signals
  logic         ex_pipeline_flush;
  logic [31:0]  ex_npc;
  logic [31:0]  ex_npc_comb;
  logic         ex_pc_sel;
  logic [31:0]  ex_target_pc;
  logic [31:0]  ex_rs2;
  logic [31:0]  ex_alu_res;
  logic [4:0]   ex_rd_addr;
  logic         ex_mem_we;
  logic         ex_reg_write;
  wb_sel_e      ex_wb_sel;

  // Signals to the Data memory
  logic [31:0]  dmem_addr;
  logic [31:0]  dmem_wdata;
  logic [31:0]  dmem_rdata;
  logic         dmem_we;
  // ECC Error Signals (Unused since ECC is disabled)
  logic dmem_dbiterra;
  logic dmem_sbiterra;

  // Mem stage output signals
  logic [31:0] mem_rdata;
  logic [31:0] mem_npc;
  logic [31:0] mem_alu_res;
  logic [4:0]  mem_rd_addr;
  logic        mem_reg_write;
  wb_sel_e     mem_wb_sel;

  // Write back stage output signals
  logic [31:0] wb_data;
  logic [4:0]  wb_rd_addr;
  logic        wb_id_we;

  // Register file direct outputs for LEDs
  logic [31:0] rf_x1, rf_x2;
  assign led_o = {rf_x2[7:0], rf_x1[7:0]};

  // Assignments
  // Mux to select next PC, high = branch taken
  // EX correction has highest priority, then ID fast path, then sequential fetch
  // ex_pipeline_flush (= pc_sel_d, combinational) is used instead of ex_pc_sel
  // (= pc_sel_q, registered) so the PC redirects in the same cycle as the flush,
  // preventing the BRAM from fetching one extra wrong instruction.
  assign pc = ex_pipeline_flush                   ? ex_npc_comb  :
              (id_bp_taken && !ex_pipeline_flush) ? id_bp_target :
                                                    if_npc;

  // MEM->EX forwarding: use load data for LOAD instructions, ALU result otherwise
  logic [31:0] mem_fwd_data;
  assign mem_fwd_data = (mem_wb_sel == WB_MEM) ? mem_rdata : mem_alu_res;

  // Instruction fetch stage
  if_stage a_if_stage (
    .clk_i            (clk_i),
    .rst_ni           (rst_ni),
    .pipeline_flush_i (ex_pipeline_flush),
    .pc_i             (pc),
    .ir_o             (if_ir),
    .pc_o             (if_pc),
    .npc_o            (if_npc)
  );

  // Instruction decode stage
  id_stage a_id_stage (
    .clk_i            (clk_i),
    .rst_ni           (rst_ni),
    .pipeline_flush_i (ex_pipeline_flush),
    .id_pc_i          (if_pc),
    .id_npc_i         (if_npc),
    .instr_i          (if_ir),
    .wb_w_addr_i      (wb_rd_addr),
    .wb_w_data_i      (wb_data),
    .wb_we_i              (wb_id_we),
    .ex_id_branch_taken_i (ex_br_taken),
    .ex_id_is_branch_i    (ex_is_branch),
    .id_rs1_o         (id_rs1),
    .id_rs2_o         (id_rs2),
    .id_rs1_addr_o    (id_rs1_addr),
    .id_rs2_addr_o    (id_rs2_addr),
    .id_rd_addr_o     (id_rd_addr),
    .pc_o             (id_pc),
    .npc_o            (id_npc),
    .imm_o                (id_imm),
    .id_ctrl_o            (id_ctrl),
    .id_bp_taken_o        (id_bp_taken),
    .id_bp_target_o       (id_bp_target),
    .id_predict_taken_o   (id_predict_taken),
    .x1_o                 (rf_x1),
    .x2_o                 (rf_x2)
  );

  ex_stage a_ex_stage (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .ex_pc_i             (id_pc),
    .ex_npc_i            (id_npc),
    .ex_rs1_i            (id_rs1),
    .ex_rs2_i            (id_rs2),
    .ex_rd_addr_i        (id_rd_addr),
    .ex_imm_i            (id_imm),
    .ex_ex_fwd_rs1_i     (ex_alu_res),
    .ex_mem_fwd_rs1_i    (mem_fwd_data),
    .ex_rs1_reg_addr_i   (id_rs1_addr),
    .ex_ex_fwd_rs2_i     (ex_alu_res),
    .ex_mem_fwd_rs2_i    (mem_fwd_data),
    .ex_rs2_reg_addr_i   (id_rs2_addr),
    .ex_ctrl_i           (id_ctrl),
    .id_predict_taken_i  (id_predict_taken),
    .ex_npc_o            (ex_npc),
    .ex_pc_sel_o         (ex_pc_sel),
    .ex_target_pc_o      (ex_target_pc),
    .ex_rs2_o            (ex_rs2),
    .ex_alu_res_o        (ex_alu_res),
    .ex_rd_addr_o        (ex_rd_addr),
    .ex_mem_we_o         (ex_mem_we),
    .ex_reg_write_o      (ex_reg_write),
    .ex_pipeline_flush_o (ex_pipeline_flush),
    .ex_npc_comb_o       (ex_npc_comb),
    .ex_wb_sel_o         (ex_wb_sel),
    .ex_br_taken_o       (ex_br_taken),
    .ex_is_branch_o      (ex_is_branch)
  );

    mem_stage a_mem_stage (
    .clk_i                (clk_i),
    .rst_ni               (rst_ni),
    .pipeline_flush_i     (ex_pipeline_flush),
    .mem_npc_i            (ex_npc),
    .mem_wb_sel_i         (ex_wb_sel),
    .mem_alu_res_i        (ex_alu_res),     // Used as RAM address
    .mem_rs2_data_i       (ex_rs2),    // Data to be stored
    .mem_rd_addr_i        (ex_rd_addr),
    .mem_ram_we_i         (ex_mem_we),   // Control signal for RAM WE
    .mem_reg_we_i         (ex_reg_write),

    // Interface to Data RAM (Combinational)
    .mem_ram_rdata_i      (dmem_rdata),
    .mem_ram_addr_o       (dmem_addr),
    .mem_ram_wdata_o      (dmem_wdata),
    .mem_ram_we_o         (dmem_we),

    // Outputs to WB Stage Boundary (Inputs to MEM/WB Reg)
    .mem_wb_rdata_o       (mem_rdata),
    .mem_wb_alu_res_o     (mem_alu_res),
    .mem_npc_o            (mem_npc),
    .mem_wb_rd_addr_o     (mem_rd_addr),
    .mem_wb_we_o          (mem_reg_write),
    .mem_wb_sel_o         (mem_wb_sel)
  );

   // Instanciate the DATA MEM using Xilinx XMP
   // xpm_memory_spram: Single Port RAM
   // Xilinx Parameterized Macro, version 2025.2

   xpm_memory_spram #(
      .ADDR_WIDTH_A(6),              // 2^6 = 64 words
      .AUTO_SLEEP_TIME(0),           // DECIMAL
      .BYTE_WRITE_WIDTH_A(32),       // DECIMAL
      .CASCADE_HEIGHT(0),            // DECIMAL
      .ECC_BIT_RANGE("7:0"),         // String
      .ECC_MODE("no_ecc"),           // String
      .ECC_TYPE("none"),             // String
      .IGNORE_INIT_SYNTH(0),         // DECIMAL
      .MEMORY_INIT_FILE("none"),     // String
      .MEMORY_INIT_PARAM("0"),       // String
      .MEMORY_OPTIMIZATION("true"),  // String
      .MEMORY_PRIMITIVE("auto"),     // String
      .MEMORY_SIZE(2048),            // 64 words * 32 bits = 2048
      .MESSAGE_CONTROL(0),           // DECIMAL
      .RAM_DECOMP("auto"),           // String
      .READ_DATA_WIDTH_A(32),        // DECIMAL
      .READ_LATENCY_A(1),            // Set to one so data is ready in the next CC
      .READ_RESET_VALUE_A("0"),      // String
      .RST_MODE_A("SYNC"),           // String
      .SIM_ASSERT_CHK(0),            // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
      .USE_MEM_INIT(1),              // DECIMAL
      .USE_MEM_INIT_MMI(0),          // DECIMAL
      .WAKEUP_TIME("disable_sleep"), // String
      .WRITE_DATA_WIDTH_A(32),       // DECIMAL
      .WRITE_MODE_A("read_first"),   // String
      .WRITE_PROTECT(1)              // DECIMAL
   )
   xpm_memory_spram_inst (
      .dbiterra(dmem_dbiterra),             // 1-bit output: Status signal to indicate double bit error occurrence on the data output of port A.
      .douta(dmem_rdata),                   // READ_DATA_WIDTH_A-bit output: Data output for port A read operations.
      .sbiterra(dmem_sbiterra),             // 1-bit output: Status signal to indicate single bit error occurrence on the data output of port A.
      .addra(dmem_addr[7:2]),          // ADDR_WIDTH_A-bit input: Address for port A write and read operations.
      .clka(clk_i),                    // 1-bit input: Clock signal for port A.
      .dina(dmem_wdata),                     // WRITE_DATA_WIDTH_A-bit input: Data input for port A write operations.
      // Always enabled for simplicity
      .ena(1'b1),                      // 1-bit input: Memory enable signal for port A. Must be high on clock cycles when read or write operations
                                       // are initiated. Pipelined internally.

      .injectdbiterra(1'b0), // 1-bit input: Controls double bit error injection on input data when ECC enabled (Error injection capability
                                       // is not available in "decode_only" mode).

      .injectsbiterra(1'b0), // 1-bit input: Controls single bit error injection on input data when ECC enabled (Error injection capability
                                       // is not available in "decode_only" mode).

      .regcea(1'b1),                 // 1-bit input: Clock Enable for the last register stage on the output data path.
      .rsta(!rst_ni),                     // 1-bit input: Reset signal for the final port A output register stage. Synchronously resets output port
                                       // douta to the value specified by parameter READ_RESET_VALUE_A.

      .sleep(1'b0),                   // 1-bit input: sleep signal to enable the dynamic power saving feature.
      .wea(dmem_we)                        // WRITE_DATA_WIDTH_A/BYTE_WRITE_WIDTH_A-bit input: Write enable vector for port A input data port dina. 1 bit
                                       // wide when word-wide writes are used. In byte-wide write configurations, each bit controls the writing one
                                       // byte of dina to address addra. For example, to synchronously write only bits [15-8] of dina when
                                       // WRITE_DATA_WIDTH_A is 32, wea would be 4'b0010.

   );

   // End of xpm_memory_spram_inst instantiation

  wb_stage a_wb_stage (
    .wb_rdata_i    (mem_rdata),
    .wb_npc_i      (mem_npc),
    .wb_alu_res_i  (mem_alu_res),
    .wb_rd_addr_i  (mem_rd_addr),
    .wb_we_i       (mem_reg_write),
    .wb_sel_i      (mem_wb_sel),

  // Data written to the register file
    .wb_data_o     (wb_data),
    .wb_rd_addr_o  (wb_rd_addr),
    .wb_we_o       (wb_id_we)
);

  endmodule
