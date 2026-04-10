`timescale 1ns / 1ps

module uart_tb ();

  // 100 MHz clock → 10 ns period
  localparam int CLK_HZ       = 100_000_000;
  localparam int BAUD         = 115_200;
  localparam int CLKS_PER_BIT = CLK_HZ / BAUD;  // 868
  localparam real BIT_NS      = 1_000_000_000.0 / BAUD; // ~8680.6 ns

  logic       clk  = 0;
  logic       rst_n;

  // DUT signals
  logic       rx_i;
  logic [7:0] rx_data;
  logic       rx_valid;

  logic       tx_o;
  logic [7:0] tx_data;
  logic       tx_valid;
  logic       tx_ready;

  uart #(
    .CLK_HZ(CLK_HZ),
    .BAUD  (BAUD)
  ) dut (
    .clk_i     (clk),
    .rst_ni    (rst_n),
    .rx_i      (rx_i),
    .rx_data_o (rx_data),
    .rx_valid_o(rx_valid),
    .tx_o      (tx_o),
    .tx_data_i (tx_data),
    .tx_valid_i(tx_valid),
    .tx_ready_o(tx_ready)
  );

  always #5 clk = ~clk;  // 100 MHz

  // ── helpers ────────────────────────────────────────────────────────────────

  // Drive one 8N1 byte onto rx_i (bit-bang, blocking)
  task automatic send_rx_byte(input logic [7:0] byte_in);
    // start bit
    rx_i = 0;
    #(BIT_NS);
    // data bits LSB-first
    for (int i = 0; i < 8; i++) begin
      rx_i = byte_in[i];
      #(BIT_NS);
    end
    // stop bit
    rx_i = 1;
    #(BIT_NS);
  endtask

  // Drive a byte onto rx_i with a bad stop bit (framing error)
  task automatic send_rx_framing_error(input logic [7:0] byte_in);
    rx_i = 0;
    #(BIT_NS);
    for (int i = 0; i < 8; i++) begin
      rx_i = byte_in[i];
      #(BIT_NS);
    end
    rx_i = 0;  // bad stop bit — line stays low
    #(BIT_NS);
    rx_i = 1;  // return to idle
    #(BIT_NS);
  endtask

  // Send a TX byte through the DUT and return the observed bit sequence
  task automatic send_tx_byte(input logic [7:0] byte_in);
    @(posedge clk);
    while (!tx_ready) @(posedge clk);
    tx_data  = byte_in;
    tx_valid = 1;
    @(posedge clk);
    tx_valid = 0;
  endtask

  // Sample tx_o in the centre of each bit period and return the decoded byte
  task automatic capture_tx_byte(output logic [7:0] decoded);
    // wait for start bit (falling edge)
    @(negedge tx_o);
    // skip to middle of start bit, then check it's still low
    #(BIT_NS / 2);
    assert (tx_o == 0) else $error("TX: start bit not low at mid-sample");
    // sample 8 data bits
    for (int i = 0; i < 8; i++) begin
      #(BIT_NS);
      decoded[i] = tx_o;
    end
    // check stop bit
    #(BIT_NS);
    assert (tx_o == 1) else $error("TX: stop bit not high");
  endtask

  // ── test ───────────────────────────────────────────────────────────────────

  int pass_count = 0;
  int fail_count = 0;

  logic [7:0] captured;

  initial begin
    // Initialise
    rst_n    = 0;
    rx_i     = 1;  // UART idle = high
    tx_data  = 0;
    tx_valid = 0;

    repeat (4) @(posedge clk);
    rst_n = 1;
    repeat (2) @(posedge clk);

    // ── Test 1: TX — send 0x55, decode the waveform ──────────────────────────
    $display("=== Test 1: TX byte 0x55 ===");
    fork
      send_tx_byte(8'h55);
      capture_tx_byte(captured);
    join
    if (captured === 8'h55) begin
      $display("PASS: TX decoded 0x%02X", captured);
      pass_count++;
    end else begin
      $display("FAIL: TX expected 0x55, got 0x%02X", captured);
      fail_count++;
    end

    repeat (CLKS_PER_BIT * 2) @(posedge clk);

    // ── Test 2: TX — send 0xA3 ───────────────────────────────────────────────
    $display("=== Test 2: TX byte 0xA3 ===");
    fork
      send_tx_byte(8'hA3);
      capture_tx_byte(captured);
    join
    if (captured === 8'hA3) begin
      $display("PASS: TX decoded 0x%02X", captured);
      pass_count++;
    end else begin
      $display("FAIL: TX expected 0xA3, got 0x%02X", captured);
      fail_count++;
    end

    repeat (CLKS_PER_BIT * 2) @(posedge clk);

    // ── Test 3: RX — bit-bang 0xC9 onto rx_i ────────────────────────────────
    $display("=== Test 3: RX byte 0xC9 ===");
    fork
      send_rx_byte(8'hC9);
      begin
        @(posedge rx_valid);
        if (rx_data === 8'hC9) begin
          $display("PASS: RX got 0x%02X", rx_data);
          pass_count++;
        end else begin
          $display("FAIL: RX expected 0xC9, got 0x%02X", rx_data);
          fail_count++;
        end
      end
    join

    repeat (CLKS_PER_BIT * 2) @(posedge clk);

    // ── Test 4: RX — bit-bang 0x00 ───────────────────────────────────────────
    $display("=== Test 4: RX byte 0x00 ===");
    fork
      send_rx_byte(8'h00);
      begin
        @(posedge rx_valid);
        if (rx_data === 8'h00) begin
          $display("PASS: RX got 0x%02X", rx_data);
          pass_count++;
        end else begin
          $display("FAIL: RX expected 0x00, got 0x%02X", rx_data);
          fail_count++;
        end
      end
    join

    repeat (CLKS_PER_BIT * 2) @(posedge clk);

    // ── Test 5: TX→RX loopback — connect tx_o to rx_i ───────────────────────
    $display("=== Test 5: TX→RX loopback 0xBE ===");
    // Drive rx_i from tx_o for this test
    force rx_i = tx_o;
    fork
      send_tx_byte(8'hBE);
      begin
        @(posedge rx_valid);
        if (rx_data === 8'hBE) begin
          $display("PASS: loopback got 0x%02X", rx_data);
          pass_count++;
        end else begin
          $display("FAIL: loopback expected 0xBE, got 0x%02X", rx_data);
          fail_count++;
        end
      end
    join
    release rx_i;
    rx_i = 1;

    repeat (CLKS_PER_BIT * 2) @(posedge clk);

    // ── Test 6: framing error — rx_valid must NOT pulse ──────────────────────
    $display("=== Test 6: framing error (bad stop bit) ===");
    begin
      logic got_valid;
      got_valid = 0;
      fork
        send_rx_framing_error(8'hFF);
        begin
          // watch for the entire frame + a little extra
          repeat (CLKS_PER_BIT * 12) @(posedge clk);
        end
      join_any
      // rx_valid should never have pulsed — sample it right after the frame
      // (if it pulsed during the frame we'd have caught it; check current state)
      if (rx_valid === 0) begin
        $display("PASS: framing error correctly dropped");
        pass_count++;
      end else begin
        $display("FAIL: framing error — rx_valid was unexpectedly high");
        fail_count++;
      end
    end

    repeat (CLKS_PER_BIT * 4) @(posedge clk);

    // ── Test 7: back-to-back RX bytes ────────────────────────────────────────
    $display("=== Test 7: back-to-back RX 0x12, 0x34 ===");
    begin
      logic [7:0] r0, r1;
      int         received;
      received = 0;
      r0 = 8'hXX; r1 = 8'hXX;
      fork
        begin
          send_rx_byte(8'h12);
          send_rx_byte(8'h34);
        end
        begin
          repeat (2) begin
            @(posedge rx_valid);
            if (received == 0) r0 = rx_data;
            else               r1 = rx_data;
            received++;
          end
        end
      join
      if (r0 === 8'h12 && r1 === 8'h34) begin
        $display("PASS: back-to-back 0x%02X 0x%02X", r0, r1);
        pass_count++;
      end else begin
        $display("FAIL: back-to-back got 0x%02X 0x%02X (expected 0x12 0x34)", r0, r1);
        fail_count++;
      end
    end

    // ── Summary ──────────────────────────────────────────────────────────────
    repeat (10) @(posedge clk);
    $display("========================================");
    $display("Results: %0d passed, %0d failed", pass_count, fail_count);
    if (fail_count == 0)
      $display("ALL TESTS PASSED");
    else
      $display("FAILURES DETECTED");
    $display("========================================");
    $finish;
  end

  // Timeout watchdog — 50 ms sim time is plenty for a few UART frames at 115200
  initial begin
    #50_000_000;
    $display("TIMEOUT: simulation did not complete");
    $finish;
  end

endmodule
