`timescale 1ns / 1ps
//
// bootloader_tb.sv
//
// Integration test: drives the full bootloader protocol over the UART port of
// primus_risc_v_top and verifies:
//   1. The bootloader sends ACK 0x06 after receiving the program.
//   2. The loaded program actually executes (x1 = 0x42 after `li x1, 0x42`).
//
// Test program loaded at 0x0400:
//   addi x1, x0, 0x42   -> 0x04200093
//   jal  x0, 0           -> 0x0000006F  (spin forever)
//

module bootloader_tb();

  localparam int  CLK_HZ       = 100_000_000;
  localparam int  BAUD         = 115_200;
  localparam int  CLKS_PER_BIT = CLK_HZ / BAUD;          // 868
  localparam real BIT_NS       = 1_000_000_000.0 / BAUD; // ~8680.6 ns

  logic        clk   = 0;
  logic        rst_n;
  logic        uart_rx;
  logic        uart_tx;
  logic [15:0] leds;

  always #5 clk = ~clk;  // 100 MHz

  primus_risc_v_top dut (
    .clk_i     (clk),
    .rst_ni    (rst_n),
    .led_o     (leds),
    .uart_rx_i (uart_rx),
    .uart_tx_o (uart_tx)
  );

  // ── helpers ────────────────────────────────────────────────────────────────

  // Drive one 8N1 byte onto uart_rx (bit-bang, blocking)
  task automatic send_byte(input logic [7:0] b);
    uart_rx = 0; #(BIT_NS);          // start bit
    for (int i = 0; i < 8; i++) begin
      uart_rx = b[i]; #(BIT_NS);     // data bits LSB-first
    end
    uart_rx = 1; #(BIT_NS);          // stop bit
  endtask

  // Sample one 8N1 byte from uart_tx
  task automatic recv_byte(output logic [7:0] b);
    @(negedge uart_tx);               // wait for start bit falling edge
    #(BIT_NS / 2);                    // skip to mid-start
    assert (uart_tx == 0) else $error("RX: start bit not low");
    for (int i = 0; i < 8; i++) begin
      #(BIT_NS);
      b[i] = uart_tx;
    end
    #(BIT_NS);
    assert (uart_tx == 1) else $error("RX: stop bit not high");
  endtask

  // ── test program ───────────────────────────────────────────────────────────
  // addi x1, x0, 0x42  =>  0x04200093  (li x1, 0x42)
  // jal  x0, 0          =>  0x0000006F  (spin)
  //
  // Bytes sent little-endian (the bootloader assembles 4 bytes into a word):
  localparam int PROG_BYTES = 8;
  logic [7:0] prog [0:PROG_BYTES-1] = '{
    8'h93, 8'h00, 8'h20, 8'h04,   // word 0: 0x04200093  (addi x1, x0, 0x42)
    8'h6F, 8'h00, 8'h00, 8'h00    // word 1: 0x0000006F  (jal  x0, 0)
  };

  // ── main test ──────────────────────────────────────────────────────────────
  int pass_count = 0;
  int fail_count = 0;
  logic [7:0] ack;

  initial begin
    rst_n   = 0;
    uart_rx = 1;                    // UART line idles high

    repeat (10) @(posedge clk);
    rst_n = 1;
    $display("--- Reset released, bootloader running ---");
    repeat (5) @(posedge clk);

    // ── Step 1: magic byte ──────────────────────────────────────────────────
    $display("Sending magic byte 0x55...");
    send_byte(8'h55);

    // ── Step 2: 4-byte little-endian length ─────────────────────────────────
    $display("Sending length (%0d bytes)...", PROG_BYTES);
    send_byte(PROG_BYTES[7:0]);
    send_byte(8'h00);
    send_byte(8'h00);
    send_byte(8'h00);

    // ── Step 3+4: send binary and await ACK (overlapped) ───────────────────
    // The bootloader starts transmitting the ACK while the last send_byte is
    // still driving the stop bit, so recv_byte must be armed before the last
    // byte is sent — otherwise the start-bit negedge is already past by the
    // time recv_byte waits for it, causing a mid-byte mis-sample.
    // The global 500 ms timeout handles the hung case.
    $display("Sending program binary (ACK monitor armed)...");
    fork
      begin
        for (int i = 0; i < PROG_BYTES; i++)
          send_byte(prog[i]);
      end
      recv_byte(ack);
    join

    if (ack === 8'h06) begin
      $display("PASS: Got ACK 0x06");
      pass_count++;
    end else begin
      $display("FAIL: Expected ACK 0x06, got 0x%02X", ack);
      fail_count++;
    end

    // ── Step 5: let the loaded program run ─────────────────────────────────
    // Give the CPU time to execute `addi x1, x0, 0x42` and `jal x0, 0`
    repeat (50) @(posedge clk);

    // ── Step 6: verify x1 = 0x42 ───────────────────────────────────────────
    if (dut.a_id_stage.a_id_regfile.x_reg_q[1] === 32'h42) begin
      $display("PASS: x1 = 0x42 — loaded program executed correctly");
      pass_count++;
    end else begin
      $display("FAIL: x1 = 0x%08X, expected 0x42",
               dut.a_id_stage.a_id_regfile.x_reg_q[1]);
      fail_count++;
    end

    // ── Summary ─────────────────────────────────────────────────────────────
    $display("========================================");
    $display("Results: %0d passed, %0d failed", pass_count, fail_count);
    if (fail_count == 0)
      $display("ALL TESTS PASSED");
    else
      $display("FAILURES DETECTED");
    $display("========================================");
    $finish;
  end

  // Global timeout — 500 ms sim time
  initial begin
    #500_000_000;
    $display("GLOBAL TIMEOUT");
    $finish;
  end

endmodule
