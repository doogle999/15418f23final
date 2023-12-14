#!/bin/bash

sourceFile=$1
baseFile=${sourceFile%%.*}

riscv32-unknown-linux-gnu-gcc -c ${sourceFile} -o ${baseFile}.o -march=rv32id -mabi=ilp32d
# Sanity
# riscv32-unknown-linux-gnu-objdump -m riscv -D ${baseFile}.o

# Find the entry point
riscv32-unknown-linux-gnu-nm  ${baseFile}.o | sed -nr 's/([0-9]{8}) T main/\1/p' > ${baseFile}.entry

riscv32-unknown-linux-gnu-objcopy -O binary -j .text ${baseFile}.o ${baseFile}.bin
# Sanity
#riscv32-unknown-linux-gnu-objdump -m riscv -b binary -D ${baseFile}.bin
