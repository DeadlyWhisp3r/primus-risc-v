#!/usr/bin/env python3
"""
load.py  <serial-port>  <program.bin>

Sends a compiled RISC-V binary to the primus-risc-v bootloader over UART.

Protocol:
  host → FPGA : 0x55          magic byte
  host → FPGA : <length>      4 bytes, little-endian (padded to multiple of 4)
  host → FPGA : <binary>      N bytes of program
  FPGA → host : 0x06          ACK on success

Example:
  python3 load.py /dev/ttyUSB0 program.bin
"""
import serial, struct, sys, time

MAGIC   = b'\x55'
ACK     = b'\x06'
BAUD    = 115200
TIMEOUT = 10  # seconds to wait for ACK

if len(sys.argv) != 3:
    print(f"Usage: {sys.argv[0]} <port> <binary>")
    sys.exit(1)

port_name = sys.argv[1]
bin_path  = sys.argv[2]

data = open(bin_path, 'rb').read()
pad  = (4 - len(data) % 4) % 4
data += b'\x00' * pad

print(f"Opening {port_name} at {BAUD} baud")
port = serial.Serial(port_name, BAUD, timeout=TIMEOUT)
time.sleep(0.1)  # let the UART settle
port.reset_input_buffer()

print(f"Sending magic byte...")
port.write(MAGIC)

print(f"Sending length: {len(data)} bytes")
port.write(struct.pack('<I', len(data)))

print(f"Sending binary...")
port.write(data)
port.flush()

print(f"Waiting for ACK...")
ack = port.read(1)

if ack == ACK:
    print("Load OK — program is running at 0x0400")
else:
    print(f"Error: expected ACK 0x06, got {ack!r}")
    sys.exit(1)

port.close()
