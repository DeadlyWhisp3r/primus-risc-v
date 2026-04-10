`timescale 1ns / 1ps

// 8N1 UART — 115200 baud at 100 MHz
// RX: two-FF synchroniser, mid-bit sampling, silent framing-error drop
// TX: ready/valid handshake, idles high
module uart #(
  parameter int CLK_HZ = 100_000_000,
  parameter int BAUD   = 115_200
)(
  input  logic       clk_i,
  input  logic       rst_ni,

  // RX — from board pin (async)
  input  logic       rx_i,
  output logic [7:0] rx_data_o,
  output logic       rx_valid_o,  // pulses high for exactly 1 cycle when byte ready

  // TX — to board pin
  output logic       tx_o,
  input  logic [7:0] tx_data_i,
  input  logic       tx_valid_i,  // strobe: assert for 1 cycle when tx_ready_o is high
  output logic       tx_ready_o   // high when idle and ready to accept a byte
);

  localparam int CLKS_PER_BIT = CLK_HZ / BAUD;  // 868 @ 100 MHz / 115200

  // -------------------------------------------------------------------------
  // RX
  // -------------------------------------------------------------------------
  typedef enum logic [1:0] { RX_IDLE, RX_START, RX_DATA, RX_STOP } rx_state_e;

  rx_state_e                        rx_state;
  logic [$clog2(CLKS_PER_BIT)-1:0] rx_cnt;
  logic [2:0]                       rx_bit_idx;
  logic [7:0]                       rx_shift;
  logic                             rx_sync1, rx_sync2;  // two-FF metastability guard

  // Bring async RX line into the clock domain
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rx_sync1 <= 1'b1;
      rx_sync2 <= 1'b1;
    end else begin
      rx_sync1 <= rx_i;
      rx_sync2 <= rx_sync1;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rx_state   <= RX_IDLE;
      rx_cnt     <= '0;
      rx_bit_idx <= '0;
      rx_shift   <= '0;
      rx_data_o  <= '0;
      rx_valid_o <= 1'b0;
    end else begin
      rx_valid_o <= 1'b0;  // default: de-assert every cycle

      case (rx_state)

        RX_IDLE: begin
          if (!rx_sync2) begin  // falling edge = start bit
            rx_state <= RX_START;
            rx_cnt   <= '0;
          end
        end

        // Wait half a bit period then re-check — filters glitches on the line
        RX_START: begin
          if (rx_cnt == (CLKS_PER_BIT / 2) - 1) begin
            if (!rx_sync2) begin
              rx_state   <= RX_DATA;
              rx_cnt     <= '0;
              rx_bit_idx <= '0;
            end else begin
              rx_state <= RX_IDLE;  // glitch, abort
            end
          end else begin
            rx_cnt <= rx_cnt + 1;
          end
        end

        // Sample each data bit at the centre of its window (LSB first per UART spec)
        RX_DATA: begin
          if (rx_cnt == CLKS_PER_BIT - 1) begin
            rx_cnt               <= '0;
            rx_shift[rx_bit_idx] <= rx_sync2;
            if (rx_bit_idx == 3'h7) begin
              rx_state <= RX_STOP;
            end else begin
              rx_bit_idx <= rx_bit_idx + 1;
            end
          end else begin
            rx_cnt <= rx_cnt + 1;
          end
        end

        RX_STOP: begin
          if (rx_cnt == CLKS_PER_BIT - 1) begin
            rx_state <= RX_IDLE;
            rx_cnt   <= '0;
            if (rx_sync2) begin       // valid stop bit (line high)
              rx_data_o  <= rx_shift;
              rx_valid_o <= 1'b1;
            end
            // framing error (stop bit low): silently drop the byte
          end else begin
            rx_cnt <= rx_cnt + 1;
          end
        end

        default: rx_state <= RX_IDLE;
      endcase
    end
  end

  // -------------------------------------------------------------------------
  // TX
  // -------------------------------------------------------------------------
  typedef enum logic [1:0] { TX_IDLE, TX_START, TX_DATA, TX_STOP } tx_state_e;

  tx_state_e                        tx_state;
  logic [$clog2(CLKS_PER_BIT)-1:0] tx_cnt;
  logic [2:0]                       tx_bit_idx;
  logic [7:0]                       tx_shift;

  assign tx_ready_o = (tx_state == TX_IDLE);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      tx_state   <= TX_IDLE;
      tx_o       <= 1'b1;  // UART idles high
      tx_cnt     <= '0;
      tx_bit_idx <= '0;
      tx_shift   <= '0;
    end else begin
      case (tx_state)

        TX_IDLE: begin
          tx_o <= 1'b1;
          if (tx_valid_i) begin
            tx_shift <= tx_data_i;
            tx_state <= TX_START;
            tx_cnt   <= '0;
          end
        end

        TX_START: begin
          tx_o <= 1'b0;  // start bit
          if (tx_cnt == CLKS_PER_BIT - 1) begin
            tx_state   <= TX_DATA;
            tx_cnt     <= '0;
            tx_bit_idx <= '0;
          end else begin
            tx_cnt <= tx_cnt + 1;
          end
        end

        TX_DATA: begin
          tx_o <= tx_shift[tx_bit_idx];  // LSB first
          if (tx_cnt == CLKS_PER_BIT - 1) begin
            tx_cnt <= '0;
            if (tx_bit_idx == 3'h7) begin
              tx_state <= TX_STOP;
            end else begin
              tx_bit_idx <= tx_bit_idx + 1;
            end
          end else begin
            tx_cnt <= tx_cnt + 1;
          end
        end

        TX_STOP: begin
          tx_o <= 1'b1;  // stop bit
          if (tx_cnt == CLKS_PER_BIT - 1) begin
            tx_state <= TX_IDLE;
            tx_cnt   <= '0;
          end else begin
            tx_cnt <= tx_cnt + 1;
          end
        end

        default: tx_state <= TX_IDLE;
      endcase
    end
  end

endmodule
