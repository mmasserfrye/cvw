# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

TARGET = debug

$(TARGET).elf.memfile:$(TARGET).elf $(TARGET).elf.objdump.addr
	riscv64-unknown-elf-elf2hex --bit-width $(if $(findstring rv64,$*),64,32) --input $< --output $@

$(TARGET).elf.objdump.addr: $(TARGET).elf.objdump
	extractFunctionRadix.sh $<

$(TARGET).elf.objdump: $(TARGET).elf
	riscv64-unknown-elf-objdump -D $(TARGET).elf > $(TARGET).elf.objdump
    
$(TARGET).elf: $(TARGET).S Makefile
	riscv64-unknown-elf-gcc -g -o $(TARGET).elf -march=rv64gc -mabi=lp64 -mcmodel=medany \
	    -nostartfiles -T$(WALLY)/examples/link/link.ld $(TARGET).S 

sim:
	spike --isa=rv64gc +signature=$(TARGET).signature.output +signature-granularity=8 $(TARGET).elf
	diff --ignore-case $(TARGET).signature.output $(TARGET).reference_output || exit
	echo "Signature matches! Success!"

clean:
	rm -f $(TARGET).elf $(TARGET).elf.*



