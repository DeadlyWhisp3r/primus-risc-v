`timescale 1ns / 1ps
import primus_core_pkg::*;

module primus_risc_v_top(
  // Input for top module
  input  logic        clk_i,
  input  logic        rst_ni,
  // LED outputs: LED[7:0] = x1[7:0], LED[15:8] = x2[7:0]
  output logic [15:0] led_o,
  // UART (USB-UART bridge on Nexys 4)
  input  logic        uart_rx_i,
  output logic        uart_tx_o
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
  mem_op_e      ex_mem_op;

  // Signals to the Data memory
  logic [31:0]  dmem_addr;
  logic [31:0]  dmem_wdata;
  logic [31:0]  dmem_rdata;
  logic [3:0]   dmem_we;
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

  // -----------------------------------------------------------------------
  // UART peripheral — memory mapped at 0x0000_2000
  //   0x2000  UART_TX  (SW: write byte to transmit)
  //   0x2004  UART_RX  (LW: read last received byte)
  //   0x2008  UART_ST  (LW: bit0 = tx_ready, bit1 = rx_data_valid)
  // -----------------------------------------------------------------------
  logic [7:0] uart_rx_data;
  logic       uart_rx_valid;   // 1-cycle pulse from uart module
  logic [7:0] uart_tx_data_in;
  logic       uart_tx_valid;
  logic       uart_tx_ready;

  // Capture RX byte; stays valid until CPU reads UART_RX
  logic [7:0] uart_rx_buf;
  logic       uart_rx_buf_valid;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      uart_rx_buf       <= '0;
      uart_rx_buf_valid <= 1'b0;
    end else begin
      if (uart_rx_valid)
        uart_rx_buf <= uart_rx_data;

      // Set on new byte, clear when CPU reads UART_RX (LW, no write)
      if (uart_rx_valid)
        uart_rx_buf_valid <= 1'b1;
      // |(|dmem_we): reduction-OR collapses the 4-bit byte-enable vector to a single
      // boolean — true if any byte is being written. Negated here to detect a pure
      // read (no bytes written) to the UART_RX address, which clears the valid flag.
      else if (!(|dmem_we) && (dmem_addr == 32'h0000_2004))
        uart_rx_buf_valid <= 1'b0;
    end
  end

  // Address decode (using word-aligned address from ALU result)
  logic addr_is_uart;
  assign addr_is_uart = (dmem_addr[15:12] == 4'h2);  // 0x2000 – 0x2FFF

  // Peripheral read data mux — combinatorial, sampled by mem_stage's pipeline FF.
  // dmem_addr (= alu_res_q) is stable for the full MEM cycle, so this is captured
  // correctly by mem_wb_rdata_q at the end of the MEM stage cycle.
  logic [31:0] periph_rdata;
  always_comb begin
    if (addr_is_uart) begin
      case (dmem_addr[3:2])
        2'b00:   periph_rdata = {24'b0, uart_tx_data_in};
        2'b01:   periph_rdata = {24'b0, uart_rx_buf};
        2'b10:   periph_rdata = {30'b0, uart_rx_buf_valid, uart_tx_ready};
        default: periph_rdata = '0;
      endcase
    end else begin
      periph_rdata = dmem_rdata;
    end
  end

  // TX fires for one cycle when CPU stores to UART_TX address.
  // |dmem_we: reduction-OR — true if any byte-enable is active (i.e. a store is happening).
  assign uart_tx_valid   = |dmem_we && addr_is_uart && (dmem_addr[3:2] == 2'b00);
  assign uart_tx_data_in = dmem_wdata[7:0];

  // Address decode for instruction memory (0x0000 – 0x0FFF)
  logic addr_is_imem;
  assign addr_is_imem = (dmem_addr[15:12] == 4'h0);

  // Port B signals driven into if_stage for bootloader writes
  logic        imem_we_b;
  logic [9:0]  imem_addr_b;
  logic [31:0] imem_data_b;
  assign imem_we_b   = |dmem_we && addr_is_imem;  // reduction-OR: any active byte-enable means a store
  assign imem_addr_b = dmem_addr[11:2];
  assign imem_data_b = dmem_wdata;

  // Gate data BRAM write enable — neither UART nor imem stores should hit it.
  // {4{condition}} replicates the 1-bit address-decode result into a 4-bit mask
  // (4'b1111 or 4'b0000) so a bitwise & can zero out all byte-enables at once
  // without losing the individual per-byte pattern when the address is valid.
  logic [3:0] dmem_we_bram;
  assign dmem_we_bram = dmem_we & {4{!addr_is_uart && !addr_is_imem}};

  // Load-use hazard detection:
  // When the instruction in EX is a load (WB_MEM) and the instruction currently
  // being decoded in ID reads from the same destination register, we must stall
  // for one cycle. The BRAM output (if_ir) is the instruction being decoded in ID.
  // if_ir[19:15] = rs1, if_ir[24:20] = rs2 of the consumer instruction.
  logic load_use_hazard;
  assign load_use_hazard = !ex_pipeline_flush              // don't stall during a flush
                         && (id_ctrl.wb_sel == WB_MEM)   // instruction NOW in EX is a load
                         && id_ctrl.reg_write            // it writes to a register
                         && (id_rd_addr != 5'b0)         // rd is not x0
                         && ((if_ir[19:15] == id_rd_addr) ||  // rs1 match
                             (if_ir[24:20] == id_rd_addr));   // rs2 match

  // Assignments
  // Mux to select next PC, high = branch taken
  // Priority: EX flush > load-use stall > ID branch prediction > sequential
  // On a load-use stall, replay if_pc (= pc_q from IF stage = address of the
  // instruction currently in ID) so the BRAM re-fetches it next cycle.
  assign pc = ex_pipeline_flush                   ? ex_npc_comb  :
              load_use_hazard                     ? if_pc        :
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
    .imem_we_b_i      (imem_we_b),
    .imem_addr_b_i    (imem_addr_b),
    .imem_data_b_i    (imem_data_b),
    .ir_o             (if_ir),
    .pc_o             (if_pc),
    .npc_o            (if_npc)
  );

  // Instruction decode stage
  id_stage a_id_stage (
    .clk_i            (clk_i),
    .rst_ni           (rst_ni),
    .pipeline_flush_i (ex_pipeline_flush),
    .stall_i          (load_use_hazard),
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
    .ex_is_branch_o      (ex_is_branch),
    .ex_mem_op_o         (ex_mem_op)
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
    .mem_mem_op_i         (ex_mem_op),
    .mem_reg_we_i         (ex_reg_write),

    // Interface to Data RAM / peripheral bus (Combinational)
    .mem_ram_rdata_i      (periph_rdata),
    .mem_ram_addr_o       (dmem_addr),
    .mem_ram_wdata_o      (dmem_wdata),
    .mem_ram_wbe_o        (dmem_we),

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
      .BYTE_WRITE_WIDTH_A(8),        // DECIMAL — byte-wide enables (wea is 4 bits)
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
      .wea(dmem_we_bram)                   // WRITE_DATA_WIDTH_A/BYTE_WRITE_WIDTH_A-bit input: Write enable vector for port A input data port dina. 1 bit
                                       // wide when word-wide writes are used. In byte-wide write configurations, each bit controls the writing one
                                       // byte of dina to address addra. For example, to synchronously write only bits [15-8] of dina when
                                       // WRITE_DATA_WIDTH_A is 32, wea would be 4'b0010.

   );

   // End of xpm_memory_spram_inst instantiation

  // UART peripheral
  uart #(.CLK_HZ(100_000_000)) a_uart (
    .clk_i      (clk_i),
    .rst_ni     (rst_ni),
    .rx_i       (uart_rx_i),
    .rx_data_o  (uart_rx_data),
    .rx_valid_o (uart_rx_valid),
    .tx_o       (uart_tx_o),
    .tx_data_i  (uart_tx_data_in),
    .tx_valid_i (uart_tx_valid),
    .tx_ready_o (uart_tx_ready)
  );

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
