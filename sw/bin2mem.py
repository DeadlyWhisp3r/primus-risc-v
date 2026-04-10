#!/usr/bin/env python3
"""
bin2mem.py  <input.bin>  <output.mem>

Converts a raw binary to Vivado-compatible .mem format:
  - One 32-bit word per line
  - 8 hex digits, uppercase
  - Little-endian byte order (matches RISC-V)
  - Input is padded to a 4-byte boundary if necessary
"""
import struct, sys

if len(sys.argv) != 3:
    print(f"Usage: {sys.argv[0]} input.bin output.mem")
    sys.exit(1)

data = open(sys.argv[1], 'rb').read()

# Pad to word boundary
pad = (4 - len(data) % 4) % 4
data += b'\x00' * pad

with open(sys.argv[2], 'w') as f:
    for i in range(0, len(data), 4):
        word = struct.unpack_from('<I', data, i)[0]
        f.write(f'{word:08X}\n')

print(f"Written {len(data)//4} words to {sys.argv[2]}")
