# Simple LED test program
# Loaded to 0x0400 by bootloader
# x1[7:0]  → LED[7:0]
# x2[7:0]  → LED[15:8]

.section .text
.global _start

_start:
    li   x1, 0xAB       # lower LEDs show 0xAB
    li   x2, 0xFF       # upper LEDs show 0xCD
loop:
    j    loop            # spin forever
