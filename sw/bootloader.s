# UART Bootloader for primus-risc-v
# Runs from 0x0000, loads program to 0x0400, jumps to it.
#
# Protocol:
#   host → FPGA : 0x55 (magic)
#   host → FPGA : 4 bytes, little-endian program length (must be multiple of 4)
#   host → FPGA : N bytes of program binary
#   FPGA → host : 0x06 (ACK)
#   CPU  jumps to 0x0400
#
# Register map:
#   s0 = UART base (0x2000)
#        0(s0) = UART_TX      write-only
#        4(s0) = UART_RX      read-only, [7:0] = received byte
#        8(s0) = UART_STATUS  bit0=tx_ready  bit1=rx_valid
#   s1 = bytes remaining to receive
#   s2 = destination write pointer (starts at 0x0400)
#   t0 = scratch / received byte
#   t1 = scratch
#   t2 = 32-bit word being assembled from 4 received bytes

.section .text
.global _start

_start:
    nop                     # absorb BRAM reset latency (first fetch is lost)
    lui  s0, 0x2            # s0 = 0x00002000  (UART base)

# ── Wait for magic byte 0x55 ────────────────────────────────────────────────
wait_magic:
    lw   t0, 8(s0)          # read UART_STATUS
    andi t0, t0, 2          # test rx_valid (bit 1)
    beqz t0, wait_magic
    lw   t0, 4(s0)          # read UART_RX
    li   t1, 0x55
    bne  t0, t1, wait_magic # not magic — keep waiting

# ── Receive 4-byte little-endian program length into s1 ─────────────────────

    # byte 0 — LSB
1:  lw   t0, 8(s0)
    andi t0, t0, 2
    beqz t0, 1b
    lw   t0, 4(s0)
    mv   s1, t0

    # byte 1
1:  lw   t0, 8(s0)
    andi t0, t0, 2
    beqz t0, 1b
    lw   t0, 4(s0)
    slli t0, t0, 8
    or   s1, s1, t0

    # byte 2
1:  lw   t0, 8(s0)
    andi t0, t0, 2
    beqz t0, 1b
    lw   t0, 4(s0)
    slli t0, t0, 16
    or   s1, s1, t0

    # byte 3 — MSB
1:  lw   t0, 8(s0)
    andi t0, t0, 2
    beqz t0, 1b
    lw   t0, 4(s0)
    slli t0, t0, 24
    or   s1, s1, t0

    li   s2, 0x400           # destination: start of loaded program area

# ── Main receive loop: 4 bytes → 1 word → SW ────────────────────────────────
recv_loop:
    beqz s1, send_ack        # no bytes left → done

    # byte 0 of word
1:  lw   t0, 8(s0)
    andi t0, t0, 2
    beqz t0, 1b
    lw   t2, 4(s0)           # t2 = byte 0

    # byte 1
1:  lw   t0, 8(s0)
    andi t0, t0, 2
    beqz t0, 1b
    lw   t0, 4(s0)
    slli t0, t0, 8
    or   t2, t2, t0          # t2 |= byte 1 << 8

    # byte 2
1:  lw   t0, 8(s0)
    andi t0, t0, 2
    beqz t0, 1b
    lw   t0, 4(s0)
    slli t0, t0, 16
    or   t2, t2, t0          # t2 |= byte 2 << 16

    # byte 3
1:  lw   t0, 8(s0)
    andi t0, t0, 2
    beqz t0, 1b
    lw   t0, 4(s0)
    slli t0, t0, 24
    or   t2, t2, t0          # t2 |= byte 3 << 24

    sw   t2, 0(s2)           # write assembled word to instruction memory (Port B)
    addi s2, s2, 4
    addi s1, s1, -4
    j    recv_loop

# ── Send ACK 0x06 ───────────────────────────────────────────────────────────
send_ack:
1:  lw   t0, 8(s0)           # poll tx_ready (bit 0)
    andi t0, t0, 1
    beqz t0, 1b
    li   t0, 0x06
    sw   t0, 0(s0)           # write to UART_TX

# ── Jump to loaded program ───────────────────────────────────────────────────
    li   t0, 0x400
    jalr x0, 0(t0)
