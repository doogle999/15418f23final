#!/bin/bash

sourceFile=$1
baseFile=${sourceFile%%.*}

riscv32-unknown-linux-gnu-gcc -c -fPIC ${sourceFile} -o ${baseFile}.o -march=rv32id -mabi=ilp32d
# Sanity
# riscv32-unknown-linux-gnu-objdump -m riscv -D ${baseFile}.o

riscv32-unknown-linux-gnu-ld ${baseFile}.o -o ${baseFile}.ln

riscv32-unknown-linux-gnu-objdump -m riscv -D ${baseFile}.ln

# Find the entry point
riscv32-unknown-linux-gnu-nm  ${baseFile}.o | sed -nr 's/([a-f0-9]{8}) T main/\1/p' > ${baseFile}.entry

riscv32-unknown-linux-gnu-objcopy -O binary -j .text -j .rodata -j .got ${baseFile}.ln ${baseFile}.bin
# Sanity
riscv32-unknown-linux-gnu-objdump -m riscv -b binary -D ${baseFile}.bin
