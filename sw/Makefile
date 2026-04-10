CROSS  = riscv64-unknown-elf
AFLAGS = -march=rv32i -mabi=ilp32

MEM_DEST  = ../primus-risc-v.ip_user_files/mem_init_files/instructions.mem
MEM_DEST2 = ../tb/instructions.mem
MEM_DEST3 = ../primus-risc-v.runs/synth_1/instructions.mem

.PHONY: all clean install

all: instructions.mem test.bin

bootloader.elf: bootloader.s bootloader.ld
	$(CROSS)-gcc $(AFLAGS) -nostdlib -static -T bootloader.ld -o $@ $<

bootloader.bin: bootloader.elf
	$(CROSS)-objcopy -O binary $< $@

instructions.mem: bootloader.bin bin2mem.py
	python3 bin2mem.py $< $@

# Copy generated .mem to all locations Vivado searches during synthesis
install: instructions.mem
	cp instructions.mem $(MEM_DEST)
	cp instructions.mem $(MEM_DEST2)
	cp instructions.mem $(MEM_DEST3)
	@echo "Installed to all Vivado search paths"

disasm: bootloader.elf
	$(CROSS)-objdump -d $<

test.elf: test.s test.ld
	$(CROSS)-gcc $(AFLAGS) -nostdlib -static -T test.ld -o $@ $<

test.bin: test.elf
	$(CROSS)-objcopy -O binary $< $@

clean:
	rm -f bootloader.elf bootloader.bin instructions.mem test.elf test.bin
